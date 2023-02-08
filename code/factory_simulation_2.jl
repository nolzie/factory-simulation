using DataStructures
using Distributions
using StableRNGs
using Printf
using Dates
using StatsKit
using StatsPlots
using CSV
using DataFrames

### use one global variable
const n_servers = 2

### Entity data structure for each order
mutable struct Order
    id::Int64
    arrival_time::Float64    # time when the order arrives at the factory
    start_service_times::Array{Float64,1}  # array of times when the order starts construction at machine i
    completion_time::Float64 # time when the order is complete
end
# generate a newly arrived order (where paint_time and completion_time are unknown)
Order(id::Int64, arrival_time::Float64 ) = Order(id, arrival_time, Array{Float64,1}(undef,2), Inf)

### Events
abstract type Event end 

struct Arrival <: Event # order arrives
    id::Int64         # a unique event id
    time::Float64     # the time of the event 
end

mutable struct Finish <: Event # an order finishes processing at machine i
    id::Int64         # a unique event id
    time::Float64     # the time of the event
    server::Int64     # ID of the server that is finishing
end

struct Null <: Event # order arrives
    id::Int64    
end

### parameter structure
struct Parameters
    seed::Int
    T::Float64
    mean_interarrival::Float64
    mean_machine_times::Array{Float64,1}
    std_machine_time::Float64
    max_queue::Array{Int64,1}          # space available in each queue
    time_units::String
end
function write_parameters( output::IO, P::Parameters ) # function to writeout parameters
    T = typeof(P)
    for name in fieldnames(T)
        println( output, "# parameter: $name = $(getfield(P,name))" )
    end
end
write_parameters( P::Parameters ) = write_parameters( stdout, P )
function write_metadata( output::IO ) # function to writeout extra metadata
    (path, prog) = splitdir( @__FILE__ )
    println( output, "# file created by code in $(prog)" )
    t = now()
    println( output, "# file created on $(Dates.format(t, "yyyy-mm-dd at HH:MM:SS"))" )
end

### State
mutable struct SystemState
    time::Float64                               # the system time (simulation time)
    n_entities::Int64                           # the number of entities to have been served
    n_events::Int64                             # tracks the number of events to have occur + queued
    event_queue::PriorityQueue{Event,Float64}   # to keep track of future arravals/services
    order_queues::Array{Queue{Order},1}         # the system queues (1 is the arrival queue)
    in_service::Array{Union{Order,Nothing},1}   # the order currently in service at machine i if there is one
    interupts::Array{Union{Int64, Int64}, 1}    # number of times production for machine 1 is interrupted
    PTL::Float64                                # production time lost from machine 1 waiting for room in the next queue
    order_waiting::Bool                         # True if there is an order waiting, False if there isnt
    last_time::Float64                          # keep a buffer of time to allow for the calculation of PTL
    orders_processed::Int64                     # number of orders processed so far
end

function SystemState( P::Parameters ) # create an initial (empty) state
    init_time = 0.0
    init_n_entities = 0
    init_n_events = 0
    init_event_queue = PriorityQueue{Event,Float64}()
    init_order_queues = Array{Queue{Order},1}(undef,n_servers)
    for i=1:n_servers
        init_order_queues[i] = Queue{Order}()
    end
    init_in_service = Array{Union{Order,Nothing},1}(undef,n_servers)
    for i=1:n_servers
        init_in_service[i] = nothing
    end
    init_interuptions = [0, 0]
    init_PTL = 0.0
    init_order_waiting = 0
    init_last_time = 0.0
    init_orders_processed = 0

    return SystemState( init_time,
                        init_n_entities,
                        init_n_events,
                        init_event_queue,
                        init_order_queues,
                        init_in_service,
                        init_interuptions,
                        init_PTL,
                        init_order_waiting,
                        init_last_time,
                        init_orders_processed)
end

# setup random number generators
struct RandomNGs
    rng::StableRNGs.LehmerRNG
    interarrival_time::Function
    machine_times::Array{Function,1}
end
# constructor function to create all the pieces required
function RandomNGs( P::Parameters )
    rng = StableRNG( P.seed ) # create a new RNG with seed set to that required
    interarrival_time() = rand(rng, Exponential(P.mean_interarrival))  

    machine_times = Array{Function,1}(undef,n_servers)
    machine_times[1] = () -> rand(rng, Normal(P.mean_machine_times[1], P.std_machine_time))
    machine_times[2] = () -> rand(rng, Exponential(P.mean_machine_times[2]))

    return RandomNGs( rng, interarrival_time,  machine_times )
end

# initialisation function for the simulation
function initialise( P::Parameters )
    # construct random number generators and system state
    R = RandomNGs( P )
    system = SystemState( P )

    # add an arrival at time 0.0
    t0 = 0.0
    system.n_events += 1
    enqueue!( system.event_queue, Arrival(0,t0),t0)

    return (system, R)
end

### output functions (I am using formatted output, but it could use just println)
function write_state( event_file::IO, system::SystemState, event::Event, timing::AbstractString; debug_level::Int=0)
    if typeof(event) <: Finish
        type_of_event = "Finish($(event.server))"
    else
        type_of_event = typeof(event)
    end
     
    @printf(event_file,
            "%12.3f,%6d,%9s,%6s,%4d,%4d,%4d,%4d,%4d\n",
            system.time,
            event.id,
            type_of_event,
            timing,
            length(system.event_queue),
            length(system.order_queues[1] ),
            length(system.order_queues[2] ),
            system.in_service[1] ==nothing ? 0 : 1, 
            system.in_service[2] ==nothing ? 0 : 1, 
            )
end

function write_entity_header( entity_file::IO, entity )
    T = typeof( entity )
    x = Array{Any,1}(undef, length( fieldnames(typeof(entity)) ) )
    for (i,name) in enumerate(fieldnames(T))
        tmp = getfield(entity,name)
        if isa(tmp, Array)
            x[i] = join( repeat( [name], length(tmp) ), ',' )
        else
            x[i] = name
        end
    end
    println( entity_file, join( x, ',') )
end

function write_PTL(PTL_file::IO, system::SystemState)
    PTL = system.PTL
    println(PTL_file, PTL)
end

function write_Interruptions(Interupt_file::IO, system::SystemState)
    Interuptions = system.interupts
    println(Interupt_file, Interuptions[1])
end

function write_entity( entity_file::IO, entity; debug_level::Int=0)
    T = typeof( entity )
    x = Array{Any,1}(undef,length( fieldnames(typeof(entity)) ) )
    for (i,name) in enumerate(fieldnames(T))
        tmp = getfield(entity,name)
        if isa(tmp, Array)
            x[i] = join( tmp, ',' )
        else
            x[i] = tmp
        end
    end
    println( entity_file, join( x, ',') )
end

### Update functions
function update!( system::SystemState, P::Parameters, R::RandomNGs, e::Event )
    throw( DomainError("invalid event type" ) )
end

function move_to_server!( system::SystemState, R::RandomNGs, server::Integer )
    # move the order order from a queue into construction
    system.in_service[server] = dequeue!(system.order_queues[server]) 
    system.in_service[server].start_service_times[server] = system.time # start service 'now'
    completion_time = system.time + R.machine_times[server]() # best current guess at service time
    
    # create a finish event for the machine current constructing the item
    system.n_events += 1
    finish_event = Finish( system.n_events, completion_time, server )
    enqueue!( system.event_queue, finish_event, completion_time )
    return nothing
end

function update!( system::SystemState, P::Parameters, R::RandomNGs, event::Arrival )
    # create an arriving order and add it to the 1st queue
    system.n_entities += 1    # new entity will enter the system
    new_order = Order( system.n_entities, event.time )
    enqueue!(system.order_queues[1], new_order)
    
    # generate next arrival and add it to the event queue
    future_arrival = Arrival(system.n_events, system.time + R.interarrival_time())
    enqueue!(system.event_queue, future_arrival, future_arrival.time)

    # if the construction machine is available, the order goes to service
    if system.in_service[1] === nothing
        move_to_server!( system, R, 1 )
    end
    return nothing
end

function stall_event!( system::SystemState, event::Event )
    if system.order_waiting == 1
        println("order_waiting")
        system.PTL += system.time - system.last_time
    else
        println("stall_event")
        system.order_waiting = 1
    end
    # defer an event until after the next event in the list
    next_event_time = peek( system.event_queue )[2]
    event.time = next_event_time + eps() # add eps() so that this event occurs just after the next event
    enqueue!(system.event_queue, event, event.time)

    if system.interupts[2] == event.id
        # if the current stall event is the same event from the last time 
        # dont interate the interuptions
        return nothing
    else
        # if this is a new event, iterate the number of
        system.interupts[1] += 1
        system.interupts[2] = event.id
    end
    return nothing
end

function update!( system::SystemState, P::Parameters, R::RandomNGs, event::Finish )
    server = event.server
    if server < n_servers && length(system.order_queues[server+1]) >= P.max_queue[server+1]
        # if the server finishes, but there are too many people in the next queue,
        # then defer the event until the queue has space, i.e, the next finish event
        # but finding the next event is easy, and next finish is hard, so we stall by one
        stall_event!( system, event )
    else
        if system.order_waiting == 1
            print("finished")
            system.PTL = system.time - system.last_time
        end
        system.order_waiting = 0
        # otherwise treat this as normal finish of service
        departing_order = deepcopy( system.in_service[server] )
        system.in_service[server] = nothing
        
        if !isempty(system.order_queues[server]) # if someone is waiting, move them to service
            move_to_server!( system, R, server )
        end

        if server < n_servers
            # move the customer to the next queue
            enqueue!(system.order_queues[server+1], departing_order)
            if system.in_service[server+1] === nothing
                move_to_server!( system, R, server+1 )
            end
        else
            # or return the entity when it is leaving the system for good
            departing_order.completion_time = system.time
            return departing_order 
        end
    end
    return nothing
end

#run the simulation and dont write anything out to the file
function run_write!( system::SystemState, P::Parameters, R::RandomNGs, fid_state::IO, fid_entities::IO,
    fid_PTL::IO, fid_interupts::IO; output_level::Integer=2)
    # main simulation loop
    while system.time < P.T
        # if P.seed ==1 && system.time <= 1000.0
        #     println("$(system.time): ") # debug information for first few events whenb seed = 1
        # end

        # grab the next event from the event queue
        (event, time) = dequeue_pair!(system.event_queue)
        system.time = time  # advance system time to the new arrival
        system.n_events += 1      # increase the event counter
        
        # write out event and state data before event
        if output_level>=2
            write_state( fid_state, system, event, "before")
        elseif output_level==1 && typeof(event) == Arrival
            write_state( fid_state, system, event, "before")
        end
        
        # update the system based on the next event, and spawn new events. 
        # return arrived/departed customer.
        departure = update!( system, P, R, event )
         
        # write out event and state data after event for debugging
        if output_level>=2
            write_state( fid_state, system, event, "after")
        end
        
        # write out entity data if it was a departure from the system
        if departure !== nothing && output_level>=2
            write_entity( fid_entities, departure )
        end

        system.last_time = system.time

    end
    write_PTL(fid_PTL, system)
    write_Interruptions(fid_interupts, system)
    return system
end

# run the simulation but don't write anything to the file 
function run!( system::SystemState, P::Parameters, R::RandomNGs)
    # main simulation loop
    while system.time < P.T
        # if P.seed ==1 && system.time <= 1000.0
        #     println("$(system.time): ") # debug information for first few events whenb seed = 1
        # end
        # Dont start tracking key KPIs until after the burn in period
        if system.time > 5000 && system.last_time < 5000
            system.interupts = 0
            system.orders_processed = 0
            system.PTL = 0
        end

        # grab the next event from the event queue
        (event, time) = dequeue_pair!(system.event_queue)
        system.time = time  # advance system time to the new arrival
        system.n_events += 1      # increase the event counter
        
        
        # update the system based on the next event, and spawn new events. 
        # return arrived/departed customer.
        departure = update!( system, P, R, event )
        if departure != nothing
            system.orders_processed += 1
        end
        system.last_time = system.time

    end

    return system
end



function PTL(dirname, param)
    # function to extract the production time lost from each simulation
    data = []
    for i in 1:1000
        path = dirname*"seed"*string(i)*"/"*param*"/PTL.csv"
        file = CSV.read(path, DataFrame, header=false)
        push!(data, file[1,1])
    end
    return data
end

function interupts(dirname, param)
    # function to extract the interuptions from each simulation
    data = []
    for i in 1:1000
        path = dirname*"seed"*string(i)*"/"*param*"/Interupts.csv"
        file = CSV.read(path, DataFrame, header=false)
        push!(data, file[1,1])
    end
    return data
end
    

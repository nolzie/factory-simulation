include("factory_simulation_2.jl")

# inititialise
seed = 1
T = 10_000.0
mean_interarrival = 60.0 ###    units here are minutes
mean_machine_times = [25.06, 59.0]
std_machine_time = 7.185
max_queue = [typemax(Int64), 4]
time_units = "minutes"
P = Parameters( seed, T, mean_interarrival, mean_machine_times, std_machine_time,
                 max_queue, time_units)

# file directory and name; * concatenates strings.
dir = pwd()*"/data/"*"/seed"*string(P.seed) # directory name
mkpath(dir)                          # this creates the directory 
file_entities = dir*"/entities.csv"  # the name of the data file (informative) 
file_state = dir*"/state.csv"        # the name of the data file (informative) 
fid_entities = open(file_entities, "w") # open the file for writing
fid_state = open(file_state, "w")       # open the file for writing

write_metadata( fid_entities )
write_metadata( fid_state )
write_parameters( fid_entities, P )
write_parameters( fid_state, P )

# headers
write_entity_header( fid_entities,  Order(0, 0.0) )
println(fid_state,"time,event_id,event_type,timing,length_event_list,length_queue1,length_queue2,in_service1,in_service2")


# # Run the simulation with a harness
# machine_1_parameters = 15:35
# machine_2_parameters = 50:70print("stall_event")
# interarrival_time_parameters = 50:70

# for p1 in machine_1_parameters
#     for p2 in machine_2_parameters
#         for p3 in interarrival_time_parameters
#             print("New Run: ")
#             print(p1)
#             print(p2)
#             print(p3)
#             println("")
#             # Set the parameters
#             seed = 1
#             T = 10_000.0
#             mean_interarrival = p3 ###    units here are minutes
#             mean_machine_times = [p1, p2]
#             std_machine_time = 7.185
#             max_queue = [typemax(Int64), 4]
#             time_units = "minutes"
#             P = Parameters( seed, T, mean_interarrival, mean_machine_times, std_machine_time,
#                             max_queue, time_units)
#             # run the simulation
#             (system,R) = initialise( P ) 
#             run!( system, P, R, fid_state, fid_entities)
#         end
#     end
# end

machine_times = 1:30 # list of queue sizes to loop through
qs_interupts = [] # amount of interupts for a given queue size
qs_ptl = [] # amount of time lost for a given queue size
orders_complete = []

for i in machine_times
    temp_interupts = []
    temp_ptl = []
    temp_orders_complete = []
    for j in 1:1000
        seed = j
        T = 10_000.0
        mean_interarrival = 45 ###    units here are minutes
        mean_machine_times = [i, 59]
        std_machine_time = 7.185
        max_queue = [typemax(Int64), 4]

        time_units = "minutes"
        P = Parameters( seed, T, mean_interarrival, mean_machine_times, std_machine_time,
                        max_queue, time_units)

        # # # file directory and name; * concatenates strings.
        # # dir = pwd()*"/data/"*"seed"*string(P.seed)*"/"*string(P.mean_interarrival)*"-"*string(P.mean_machine_times[1])*"-"*string(P.mean_machine_times[2]) # directory name
        # # es_dir = pwd()*"/data/"*"/seed"*string(P.seed)
        # # mkpath(dir)                          # this creates the directory 
        # file_entities = es_dir*"/entities.csv"  # the name of the data file (informative) 
        # file_state = es_dir*"/state.csv"        # the name of the data file (informative) 
        # file_PTL = dir*"/PTL.csv"  # the name of the data file (informative) 
        # file_interupts = dir*"/Interupts.csv"  
        # fid_entities = open(file_entities, "w") # open the file for writing
        # fid_state = open(file_state, "w")       # open the file for writing
        # fid_PTL = open(file_PTL, "w")
        # fid_interups = open(file_interupts, "w")

        # Simple run with no harness
        (system,R) = initialise( P ) 
        system = run!( system, P, R)

        push!(temp_interupts, system.interupts[1])
        push!(temp_ptl, system.PTL)
        push!(temp_orders_complete, system.orders_processed)
    end

    push!(qs_interupts, mean(temp_interupts))
    push!(qs_ptl, mean(temp_ptl))
    push!(orders_complete, mean(temp_orders_complete))
end

# # Simple run with no harness
# (system,R) = initialise( P ) 
# run!( system, P, R, fid_state, fid_entities)

# # remember to close the files
# close(fid_PTL)
# close(fid_iterupts)
# close( fid_entities )
# close( fid_state )



# analysing queue data

print(qs_interupts)
print(qs_ptl)


plot(qs_interupts,
    title="Average Interuptions for each Mean Service Time",
    label="Avg Interuptions",
    xlabel="Mean Service Time")


plot(qs_ptl,
    title="Average PTL for a each Mean Service Time",
    label="Avg PTL",
    xlabel="Mean Service Time")


plot(orders_complete,
    title="Average OPPS for a each Mean Service Time",
    label="Avg Orders Completed",
    xlabel="Mean Service Time")


ptl_2 = []
interupts_2 = []
orders_2 = []

for i in 1:1000
    seed = i
    T = 15000
    mean_interarrival = 45 ###    units here are minutes
    mean_machine_times = [25.06, 38]
    std_machine_time = 7.185
    max_queue = [typemax(Int64), 4]

    time_units = "minutes"
    P = Parameters( seed, T, mean_interarrival, mean_machine_times, std_machine_time,
                    max_queue, time_units)

    # Simple run with no harness
    (system,R) = initialise( P ) 
    system = run!( system, P, R)

    push!(ptl_2, system.PTL)
    push!(interupts_2, system.interupts[1])
    push!(orders_2, system.orders_processed)

end

mean(ptl_2)
mean(interupts_2)
mean(orders_2)

histogram(ptl_2,
    title="Average Interuptions for each Mean Service Time",
    label="Avg Interuptions",
    xlabel="Mean Service Time")


histogram(interupts_2,
    title="Average PTL for a each Mean Service Time",
    label="Avg PTL",
    xlabel="Mean Service Time")


histogram(orders_2,
    title="Distribution of Order Processed",
    label="Count",
    xlabel="Orders")

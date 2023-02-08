using Distributions
using StatsKit
using StatsPlots
using CSV
using DataFrames

inter_arrival_param = 60
machine_1_param = 25
machine_2_param = 59

measured_data = CSV.read("/home/nolz/Documents/University/decisionScience/assessment3/data/measured_times.csv", DataFrame)

std(measured_data.machine_times_1)

histogram(measured_data.interarrival_times, 
        title= "Distribution of Inter Arrival Times",
        xlabel= "Arrival Times",
        label = "Counts")

qqplot(Normal(machine_1_param, 10), # This is the distribution you want to compare to
       measured_data.machine_times_1, # This is your dataset/sample
       title = "QQ-plot of Machine 1 Service Times vs a Normal", # Make it look pretty with labels
       xlabel = "Theoretical Quantile", ylabel = "Sample Quantile")

qqplot(Exponential(59), # This is the distribution you want to compare to
        measured_data.interarrival_times, # This is your dataset/sample
        title = "QQ-plot of Inter Arrival Times vs an Exponential", # Make it look pretty with labels
        xlabel = "Theoretical Quantile", ylabel = "Sample Quantile",
        plot_titlefontsize=font(5))


# data analysis for results
include("factory_simulation_2.jl")


T = 10_000.0
mean_interarrival = 60.0 ###    units here are minutes
mean_machine_times = [25.06, 59.0]
std_machine_time = 7.185


data_dir = pwd()*"/data/"
param = string(P.mean_interarrival)*"-"*string(P.mean_machine_times[1])*"-"*string(P.mean_machine_times[2]) 

prod_time_lost = PTL(data_dir, param)
interuptions = interupts(data_dir, param)

histogram(prod_time_lost,
          title="Production Time Lost for Each Simulation",
          xlabel="Time",
          label="Count")

histogram(interuptions,
        title="Interuptions for Each Simulation",
        xlabel="Interuptions",
        label="Count")

          
          
mean(interuptions)


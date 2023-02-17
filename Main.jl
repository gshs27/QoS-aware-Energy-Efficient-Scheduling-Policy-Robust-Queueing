using Distributions, PyPlot, JuMP, Ipopt, Dates
using DataFrames, XLSX

include("./Types.jl")
include("./Functions.jl")
pwd()

#Parameters for 5Apps - 10Server Setting
I = 5
feas_servs = [[1], [1], [1, 2], [1, 2, 3], [2, 3], [2, 3], [3], [4, 5], [4, 5], [5]]
J = 10
feas_apps = [[1, 2, 3, 4], [3, 4, 5, 6], [4, 5, 6, 7], [8, 9], [8, 9, 10]]

λₒ = [4, 2, 4, 10, 5]
SCOVₐₒ = [2, 1.5, 1, 0.8, 2]
σₐₒ = calculate_sigma_a(λₒ, SCOVₐₒ)
μₒ_inv = [5, 10, 5, 2, 3]
SCOVₛₒ = [1.5, 2, 1, 0.8, 0.5]
σₛₒ = calculate_sigma_s(μₒ_inv, SCOVₛₒ)
inter_arrival_distributions = ["LogNormal", "LogNormal", "Exponential", "LogNormal", "LogNormal"]
workload_distributions = ["LogNormal", "LogNormal", "LogNormal", "LogNormal", "LogNormal"]
ωₒ = [20, 20, 20, 20, 15]
K, α = [150, 250, 220, 150, 300, 350, 220, 350, 400, 700], [1/3, 1/5, 1, 2/3, 0.8, 0.4, 3/7, 0.5, 0.6, 4/9]
x_mins, x_maxs = [5, 7, 6, 5, 7, 8, 6, 7, 8, 10], [100, 102, 99, 105, 100, 102, 100, 105, 102, 105]


#Parameters for Simulation
const MAX_ARRIVALS = 200000
const WARM_UP_ARRIVALS = 40000
#const REPLICATION_TIME = 100000.0
#const REPLICATION_TIME = 30000.0
const REPLICATION_TIME = 5000.0
const WARM_UP_TIME = 0.2*REPLICATION_TIME
const REGULAR_UPDATE_INTERVAL = 0.05

apps_server_info_setting_5apps_10servers = Apps_Server_Info_Setting(I, feas_servs, J, feas_apps, λₒ, SCOVₐₒ, σₐₒ, μₒ_inv, SCOVₛₒ, σₛₒ, inter_arrival_distributions, workload_distributions, ωₒ)
power_info_setting_5apps_10servers = Power_Info_Setting(K, α, x_mins, x_maxs)

#Parameters for SLA
ε, δ = 0.05, 5

#Variability Parameter Coefficients learned via Quantile Regression
θ = [0.08916055,4.362735581,2.672253744,-0.973326678]

#Parameters for Optimization Solving 
x_start_dif = 20

#Solve optimization problem and obtain solution
result = calculate_routing_prob_and_server_speeds(x_start_dif, θ, δ, apps_server_info_setting_5apps_10servers, power_info_setting_5apps_10servers)

#Routing Probability and Server Speeds
routing_prob, server_speeds = result[1], result[2]
prob_dict = calculate_prob_dict(routing_prob, apps_server_info_setting_5apps_10servers)

#######Run the simulation for using static 
static_results = calculate_static_results(δ, 1-ε, prob_dict, server_speeds, apps_server_info_setting_5apps_10servers, power_info_setting_5apps_10servers)
dynamic_results = calculate_dynamic_results(δ, 1-ε, apps_server_info_setting_5apps_10servers, power_info_setting_5apps_10servers)

println("----------Static Results--------")
println("Average Power Consumption per Unit Time : ", static_results[1])
println("Violation Probability P(S>δ) for each server: ", static_results[2])
println("----------Dynamic Results--------")
println("Average Power Consumption per Unit Time : ", dynamic_results[1])
println("Violation Probability P(S>δ) for each server: ", dynamic_results[2])
#Struct for Apps-Server Information Setting
mutable struct Apps_Server_Info_Setting
  I::Int64 # Number of Applications
  #ex)  5
  feas_servs::Array{Array{Int64}} #Set of Applications which could be handled by each server
  #ex)  [[1], [1], [1, 2], [1, 2, 3], [2, 3], [2, 3], [3], [4, 5], [4, 5], [5]]
  J::Int64 # Number of Servers 10
  feas_apps::Array{Array{Int64}} #Set of servers which are feasible to handle the each application 
  #ex) [[1, 2, 3, 4], [3, 4, 5, 6], [4, 5, 6, 7], [8, 9], [8, 9, 10]]
  λₒ::Array{Float64} #Arrival Rates of each Application 
  #ex) [4, 2, 4, 10, 5]
  SCOVₐₒ::Array{Float64} #SCOV of Inter-Arrival Times of each application 
  #ex) [2, 1.5, 1, 0.8, 2]
  σₐₒ::Array{Float64} #Standard Deviation of Inter-Arrival Times of each application
  #ex)  calculate_sigma_a(λₒ, SCOVₐₒ)
  μₒ_inv::Array{Float64} #Average size of workloads of each application
  #ex)  [5, 10, 5, 2, 3]
  SCOVₛₒ::Array{Float64} #SCOV of size of workloads of each application
  #ex)  [1.5, 2, 1, 0.8, 0.5]
  σₛₒ::Array{Float64} #Standard Deviation of workload amounts of each application calculate_sigma_s(μₒ_inv, SCOVₛₒ)
  inter_arrival_distributions::Array{String} #Inter-arrival time distribution types 
  #ex) ["LogNormal", "LogNormal", "Exponential", "LogNormal", "LogNormal"]
  workload_distributions::Array{String} #Wokrload amount distribution types 
  #ex) ["LogNormal", "LogNormal", "LogNormal", "LogNormal", "LogNormal"]
  ωₒ::Array{Float64} #Instant Demand of each application
  #ex)  [20, 20, 20, 20, 15]
end

#Struct for Power Information setting
mutable struct Power_Info_Setting
  K::Array{Float64} #Power Function-related coefficient K 
  #ex) [150, 250, 220, 150, 300, 350, 220, 350, 400, 700]
  α::Array{Float64} #Power Function-related coefficient α 
  #ex) [1/3, 1/5, 1, 2/3, 0.8, 0.4, 3/7, 0.5, 0.6, 4/9]
  γs::Array{Float64} # Lower Limits of Server Speeds 
  #ex) [5, 7, 6, 5, 7, 8, 6, 7, 8, 10]
  Γs::Array{Float64} # Upper Limits of Server Speeds 
  #ex) [100, 102, 99, 105, 100, 102, 100, 105, 102, 105]
end

#Struct for Server Setting
mutable struct Server_Setting
  γ::Float64 # server speed lower bound
  Γ::Float64 # server speed upper bound
  K::Float64 # power function parameter 1
  α::Float64 # power function parameter 2
  n::Int64 # power function parameter 3
  δ::Float64 # QoS constraint parameter 1
  ϵ::Float64 # QoS constraint parameter 2
  x_0::Float64 # initial server speed
  p_0::Float64 # initial server price
  Apps::Tuple # assigned application set
end

#Struct for Workload Setting
mutable struct Workload_Setting
  instant_demand::Float64 #Insant demand rate of workload

  inter_arrival_distribution::String #Inter-arrival time distribution's Type ex) "Exponential"
  mean_inter_arrival::Float64 #Mean of inter-arrival time
  scv_inter_arrival::Float64 #Squared cofficient of variation of inter-arrival time
  std_inter_arrival::Float64 #Standard deviation of inter-arrival time

  workload_distribution::String #Workload amount distribution's Type ex) "Exponential"
  mean_workload::Float64 #Mean of workload amount
  scv_workload::Float64 #Squared cofficient of variation of workload amount
  std_workload::Float64 #Standard deviation of workload amount
end

#Struct for Arrival Information Setting
mutable struct Arrival_Information
  arrival_index::Int64        # Index(Number) of arrival(workload)
  app_type::Int64             # Type of application in which the arrival(workload) came from
  arrival_time::Float64       # The arrival time of that arrival
  remaining_workload::Float64 # Remaining amount of worklaod at certain time
  completion_time::Float64    # Estimated completion time
end

#Struct for Server
mutable struct Server
  previous_speed::Float64  # Previous operation speed of certain server
  current_speed::Float64   # Current operation speed of certain server

  previous_price::Float64  # Previous price of certain server (Used for Dynamic Control)
  current_price::Float64   # Current price of certain server (Used for Dynamic Control)

  previous_remaining_workload::Float64 # Previous total amount of remaining workload (at time t)
  current_remaining_workload::Float64  # Current total amount of remaining workload (at time t+1)

  num_in_server::Int64                        # Number of arrivals(workloads) within the server
  indices_in_server::Tuple                    # Indicies of arrivals(workloads) within the server
  κ::Float64                                  # Size of buffer of server 
  WIP::Array{Arrival_Information}             # An array which contains the workloads within the server배열
  cumulative_power_consumption::Float64       # Cumulative power consumption

  function Server(previous_speed::Float64,
                  current_speed::Float64,
                  previous_price::Float64,
                  current_price::Float64)
    #Initialization
    previous_remaining_workload = 0.0
    current_remaining_workload = 0.0
    num_in_server = 0
    indices_in_server = ()
    κ = 0.0
    WIP = Arrival_Information[]
    cumulative_power_consumption = 0.0
    new(previous_speed,
        current_speed,
        previous_price,
        current_price,
        previous_remaining_workload,
        current_remaining_workload,
        num_in_server,
        indices_in_server,
        κ,
        WIP,
        cumulative_power_consumption)
  end
end

#Struct for Virtual Data Center
mutable struct VirtualDataCenter
  ## These variables are set directly by the creator
  WS::Array{Workload_Setting}                   # An array which contains 'Workload_Setting'
  AI::Array{Arrival_Information}                # An array which contains 'Arrival_Information'
  SS::Array{Server_Setting}                     # An array which contains 'Server_Setting'
  warm_up_arrivals::Int64                       # Number of warm-up arrival number
  max_arrivals::Int64                           # Number of maximum arrival
  warm_up_time::Float64                         # Warm-up time
  replication_time::Float64                     # Total simulation time
  regular_update_interval::Float64              # Time of Regular update interval
  S::Array{Server}                              # An array which contains "Server'

  ## Internal variables - Set by constructor
  passed_arrivals::Int64              # Number of arrivals that has been already processed
  current_time::Float64               # Current time of simulator
  inter_event_time::Float64           # Time gap between last event and current event
  warmed_up::Bool                     # Binary variable which indicates whether warm up is done(1) or not(0)
  next_arrival::Float64               # Next arrival time
  next_completion::Float64            # Next completion time
  next_completion_info::Dict          # Information about next completion (Server Number, Arrival Information Number)
  next_regular_update::Float64        # Next (regular) update time of Speed & Price
  next_buffer_update::Float64         # Next update time of buffer
  buffer_update_counter::Int64        # Counter for the buffer update count
  total_cumulative_power_consumption::Float64   # Total cumulative power consumption

  # constructor definition
  function VirtualDataCenter(WS::Array{Workload_Setting},
                             AI::Array{Arrival_Information},
                             SS::Array{Server_Setting},
                             warm_up_arrivals::Int64,
                             max_arrivals::Int64,
                             warm_up_time::Float64,
                             replication_time::Float64,
                             regular_update_interval::Float64,
                             S::Array{Server})
   #Initialization
   passed_arrivals = 0       
   current_time = 0.00       
   inter_event_time = 0.00   
   warmed_up = false
   next_arrival = AI[1].arrival_time
   next_completion = typemax(Float64)
   next_completion_info = Dict()
   next_regular_update = regular_update_interval
   next_buffer_update = 0.0
   buffer_update_counter = 0
   total_cumulative_power_consumption = 0.0

    new(WS,
        AI,
        SS,
        warm_up_arrivals,
        max_arrivals,
        warm_up_time,
        replication_time,
        regular_update_interval,
        S,
        passed_arrivals,
        current_time,
        inter_event_time,
        warmed_up,
        next_arrival,
        next_completion,
        next_completion_info,
        next_regular_update,
        next_buffer_update,
        buffer_update_counter,
        total_cumulative_power_consumption)
  end
end

#Struct for Plot Information
mutable struct Plot_Information
  time_array::Array{Float64}  #Array which containts the time
  speed_array::Array{Array{Float64}} #Array which contains the server speeds
  price_array::Array{Array{Float64}} #Array which contains the server prices
  sojourn_time_violation_array::Array{Array{Float64}} #Array which contains an binary variable whether an arrival violated the SLA or not
  sojourn_time_array::Array{Array{Float64}} #Array which contains sojourn times of arrivals for servers
  buffer_array::Array{Array{Float64}} #Array which contains the buffer for servers
  cumulative_power_consumption_array::Array{Array{Float64}} #Array which contains cumulative power consumptions of arrival for servers
  total_cumulative_power_consumption_array::Array{Float64} #Array which contains the total cumulative power consumptions for servers
  num_in_server_array::Array{Array{Float64}} #arraya which contains number of arrivals within servers
  file_sim_record::IOStream #Directory for detailed simulation record file
  file_summarization::IOStream #Directory for simulation summary file
  function Plot_Information(S::Array{Server}, _file_sim_record::IOStream, _file_summarization::IOStream)
    time_array = Float64[]
    speed_array = Array{Float64}[]
    price_array = Array{Float64}[]
    sojourn_time_violation_array = Array{Float64}[]
    sojourn_time_array = Array{Float64}[]
    buffer_array = Array{Float64}[]
    cumulative_power_consumption_array = Array{Float64}[]
    total_cumulative_power_consumption_array = Float64[]
    num_in_server_array = Array{Float64}[]
    for j = 1:length(S)
      push!(speed_array, Float64[])
      push!(price_array, Float64[])
      push!(sojourn_time_violation_array, Float64[])
      push!(sojourn_time_array, Float64[])
      push!(buffer_array, Float64[])
      push!(cumulative_power_consumption_array, Float64[])
      push!(num_in_server_array, Float64[])
    end
    file_sim_record = _file_sim_record
    file_summarization = _file_summarization
    new(time_array, speed_array, price_array, sojourn_time_violation_array, sojourn_time_array, buffer_array, cumulative_power_consumption_array, total_cumulative_power_consumption_array, num_in_server_array, file_sim_record, file_summarization)
  end
end

#Sturct for Job(Workload)
mutable struct JOB
  arrival_index::Int64    #An arrival index of the job
  arrival_time::Float64 #An arrival time of the job
  remaining_workload::Float64 #Reamining workload of the job
  completion_time::Float64 #Estimated completion time of the job
end

#Struct for Inter-arrival Time Random Variable
mutable struct Inter_Arrival_RV
  mean::Float64 #Mean of Workload amount random variable
  SCOV::Float64 #Squared coefficient of variation of Inter-arrival time random variable
  lambda_::Float64 #1/Mean(Arrival rate per unit time) of Inter-arrival time random variable
  sigma_::Float64 #Standard deviatio of Inter-arrival time random variable
end

#Struct for Workload Amount Random Variable
mutable struct Workload_RV
  mean::Float64 #Mean of Workload amount random variable
  SCOV::Float64 #Squared coefficient of variation of Workload amount random variable
  mu_::Float64 #1/Mean(Arrival rate per unit time) of Workload amount random variable
  sigma_::Float64 #Standard deviatio of Workload amount random variable
end

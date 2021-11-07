#Functions

#########Fucntions for Dynamic Control#############
#########Neccessary for real-time variable update calculation#####
#Server's Power function C(x) - Cubic Form by Wierman et al.
function server_power(j::Int64, SS::Array{Server_Setting}, S::Array{Server})
  return SS[j].K + (SS[j].α)*(S[j].current_speed^SS[j].n)
end

#1st Differentiation of Power Function dC(x)/dx
function server_power_1st_diff(j::Int64, SS::Array{Server_Setting}, S::Array{Server})
  return (SS[j].α)*(SS[j].n)*(S[j].current_speed^((SS[j].n)-1))
end

#2nd Differentiation of Power Function d²C(x)/dx²
function server_power_2nd_diff(j::Int64, SS::Array{Server_Setting}, S::Array{Server})
  return (SS[j].α)*(SS[j].n)*((SS[j].n)-1)*(S[j].current_speed^((SS[j].n)-2))
end

#Function calculating x-dot
function x_dot(j::Int64, SS::Array{Server_Setting}, S::Array{Server})
  if SS[j].γ < S[j].current_speed < SS[j].Γ
    return S[j].current_price - server_power_1st_diff(j,SS,S)
  elseif S[j].current_speed >= SS[j].Γ
    return min( S[j].current_price - server_power_1st_diff(j,SS,S) , 0.0 )
  elseif S[j].current_speed <= SS[j].γ
    return max( S[j].current_price - server_power_1st_diff(j,SS,S) , 0.0 )
  end
end

#Function calculating p-dot
function p_dot(j::Int64, S::Array{Server})
  if S[j].current_price >= 0.0
    return S[j].κ + S[j].current_remaining_workload - S[j].current_speed
  else
    return max(S[j].κ + S[j].current_remaining_workload - S[j].current_speed, 0.0)
  end
end

#Function finding a server with minimum price (for dynamic routing)
function find_min_price_server(app_type::Int64, SS::Array{Server_Setting}, S::Array{Server})
  server_index = 0
  temp_price = typemax(Float64)

  for j in 1:length(SS)
    if in(app_type, SS[j].Apps) == true
      if temp_price > S[j].current_price
        temp_price = S[j].current_price
        server_index = j
      end
    end
  end
  return server_index
end
########################################################

###########Functions for Static Control###################
#Function finding a server to dispatch the arrival via probabilistic rule
function find_prob_server(app_type::Int64, routing_prob::Dict{Any, Any}, feas_apps::Array{Array{Int64}})
  temp_cdf = 0.0
  rand_cdf = rand()

  for j in feas_apps[app_type]
      temp_cdf += routing_prob[app_type, j]
      if rand_cdf < temp_cdf
          return j
      end
  end
end
#######################################################

##############Functions for simulation#########################
#Each functions has two different versions - Dynamic & Static

#Functions making an movement between current time to next event
function next_event_dynamic(vdc::VirtualDataCenter, PI::Plot_Information)
  if vdc.next_regular_update == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is regular update
    push!(PI.time_array, vdc.current_time) # Record the Update Time
    push!(PI.total_cumulative_power_consumption_array, vdc.total_cumulative_power_consumption) # Record the Total Cumulative Power Consumption
    inter_event_time = vdc.next_regular_update - vdc.current_time   # Save the Inter-Event Time
    vdc.current_time = vdc.next_regular_update                      # Change the current time of Simulator
    
    # Update the Remaining Workload
    for j in 1:length(vdc.S)   # For all Servers
      for i in 1:length(vdc.S[j].WIP)   # For each (Work in Progress) Arrival within the Server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #Reduce the workload of each arrival
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #Reduce the total workload of server j
      end

      # For plotting speed, price, and κ
      push!(PI.speed_array[j], vdc.S[j].current_speed)
      push!(PI.price_array[j], vdc.S[j].current_price)
      push!(PI.buffer_array[j], vdc.S[j].κ)
      push!(PI.cumulative_power_consumption_array[j], vdc.S[j].cumulative_power_consumption)
      push!(PI.num_in_server_array[j], vdc.S[j].num_in_server)

      # Update the cumulation power sumption for server j
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption

      #Update server speeds and prices
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      temp = max(vdc.SS[j].γ, (vdc.S[j].previous_speed) + ((1/server_power_2nd_diff(j, vdc.SS, vdc.S))*(x_dot(j, vdc.SS, vdc.S))))
      vdc.S[j].current_speed = min(temp, vdc.SS[j].Γ)
      vdc.S[j].previous_price = vdc.S[j].current_price
      vdc.S[j].current_price = vdc.S[j].previous_price + p_dot(j, vdc.S)
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      end
    end

    # Do the calculation for completion time of each server
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    #Update the next completion time for each server and vdc
    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    #If there exists no more arrival within data center (vdc)
    if server_index_2 == 0 && WIP_index == 0 
      vdc.next_completion = typemax(Float64)
      vdc.next_regular_update += vdc.regular_update_interval
    else
      vdc.next_regular_update += vdc.regular_update_interval
    end

  elseif vdc.next_arrival == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is due to arrival
    inter_event_time = vdc.next_arrival - vdc.current_time   # Save the Inter-Event Time
    vdc.current_time = vdc.next_arrival                      # Change the current time of Simulator
    println(PI.file_sim_record,"(Time: $(vdc.current_time)) Current event: New arrival ($(vdc.AI[1].arrival_index)th arrival, app_type: $(vdc.AI[1].app_type), workload: $(vdc.AI[1].remaining_workload), server_dispatched: $(find_min_price_server(vdc.AI[1].app_type, vdc.SS, vdc.S))")

    # Routing job and Workload increment based on the type of job and current prices of servers 
    server_index = find_min_price_server(vdc.AI[1].app_type, vdc.SS, vdc.S)    
    vdc.S[server_index].previous_remaining_workload = vdc.S[server_index].current_remaining_workload  # Save previous remaining workload
    vdc.S[server_index].current_remaining_workload = vdc.S[server_index].previous_remaining_workload + vdc.AI[1].remaining_workload # Add arriving workload to current remaining workload

    # Reducing workloads
    for j in 1:length(vdc.S)   # For all server
      for i in 1:length(vdc.S[j].WIP)   # For each arrival within server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the arrival's worklaod
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the total reamining workload
      end
      # Update cumulative power consumption of server
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption
      
      #Update server speeds and prices
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      temp = max(vdc.SS[j].γ, (vdc.S[j].previous_speed) + ((1/server_power_2nd_diff(j, vdc.SS, vdc.S))*(x_dot(j, vdc.SS, vdc.S))))
      vdc.S[j].current_speed = min(temp, vdc.SS[j].Γ)
      vdc.S[j].previous_price = vdc.S[j].current_price
      vdc.S[j].current_price = vdc.S[j].previous_price + p_dot(j, vdc.S)
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      end
    end

    # Updating next completion time
    push!(vdc.S[server_index].WIP, vdc.AI[1]) #Add a job object to WIP of routed server
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    vdc.S[server_index].num_in_server += 1 # Update the number of jobs in server
    popfirst!(vdc.AI) # Remove the arrival from Arrival Information
    vdc.next_arrival = vdc.AI[1].arrival_time
  elseif vdc.next_completion == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is due to completion
    server_index = vdc.next_completion_info["server_num"]
    WIP_index = vdc.next_completion_info["WIP_num"]
    inter_event_time = vdc.next_completion - vdc.current_time
    vdc.current_time = vdc.next_completion
    println(PI.file_sim_record,"(Time: $(vdc.current_time)) Current event: Completion ($(vdc.passed_arrivals+1)th, server: $server_index , server $server_index's remaining WIPs: $(length(vdc.S[server_index].WIP))")

    # for summarizing
    if vdc.warmed_up == true
      sojourn_time = vdc.current_time - vdc.S[server_index].WIP[WIP_index].arrival_time
      if sojourn_time > vdc.SS[server_index].δ
        push!(PI.sojourn_time_violation_array[server_index], 1)
      else
        push!(PI.sojourn_time_violation_array[server_index], 0)
      end

      push!(PI.sojourn_time_array[server_index], sojourn_time)
    end

    vdc.S[server_index].previous_remaining_workload = vdc.S[server_index].current_remaining_workload  # Save the remaining workload before update

    for j in 1:length(vdc.S)   # For all servers
      for i in 1:length(vdc.S[j].WIP)   # For all arrivals within the server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #  Reduce the arrival's worklaod
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the total reamining workload
      end
      # Update cumulative power consumption of server
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption
      
      #Update server speeds and prices
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      temp = max(vdc.SS[j].γ, (vdc.S[j].previous_speed) + ((1/server_power_2nd_diff(j, vdc.SS, vdc.S))*(x_dot(j, vdc.SS, vdc.S))))
      vdc.S[j].current_speed = min(temp, vdc.SS[j].Γ)
      vdc.S[j].previous_price = vdc.S[j].current_price
      vdc.S[j].current_price = vdc.S[j].previous_price + p_dot(j, vdc.S)
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      end
    end

    # Remove the completed job
    deleteat!(vdc.S[server_index].WIP, WIP_index)
    vdc.S[server_index].num_in_server -= 1 # Substitue 1 form number of jobs in server

    # Updating next completion time
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    if server_index_2 == 0 && WIP_index == 0 # If there is no arrival within entire vdc
      vdc.next_completion = typemax(Float64)
    end
    vdc.passed_arrivals += 1
  end
end

function next_event_static(vdc::VirtualDataCenter, PI::Plot_Information, routing_prob::Dict{Any, Any}, ro_server_speeds::Array{Float64}, feas_apps::Array{Array{Int64}})
  if vdc.next_regular_update == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is regular update
    push!(PI.time_array, vdc.current_time) # Record the Update Time
    push!(PI.total_cumulative_power_consumption_array, vdc.total_cumulative_power_consumption) # Record the Total Cumulative Power Consumption
    inter_event_time = vdc.next_regular_update - vdc.current_time   # Save the Inter-Event Time
    vdc.current_time = vdc.next_regular_update                      # Change the current time of Simulator
    
    # Update the Remaining Workload
    for j in 1:length(vdc.S)   # For all Servers
      for i in 1:length(vdc.S[j].WIP)   # For each (Work in Progress) Arrival within the Server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #Reduce the workload of each arrival
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #Reduce the total workload of server j
      end

      # For plotting speed, price, and κ
      push!(PI.speed_array[j], vdc.S[j].current_speed)
      push!(PI.price_array[j], vdc.S[j].current_price)
      push!(PI.buffer_array[j], vdc.S[j].κ)
      push!(PI.cumulative_power_consumption_array[j], vdc.S[j].cumulative_power_consumption)
      push!(PI.num_in_server_array[j], vdc.S[j].num_in_server)

      # Update the cumulation power sumption for server j
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption

      #Update server speeds
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      else
        vdc.S[j].current_speed = max(vdc.SS[j].γ, ro_server_speeds[j])
      end
    end

    # Do the calculation for completion time of each server
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    #Update the next completion time for each server and vdc
    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    #If there exists no more arrival within data center (vdc)
    if server_index_2 == 0 && WIP_index == 0 
      vdc.next_completion = typemax(Float64)
      vdc.next_regular_update += vdc.regular_update_interval
    else
      vdc.next_regular_update += vdc.regular_update_interval
    end

  elseif vdc.next_arrival == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is due to arrival
    inter_event_time = vdc.next_arrival - vdc.current_time   # Save the Inter-Event Time
    vdc.current_time = vdc.next_arrival                      # Change the current time of Simulator
    
    #Find server to be routed by probabilistic law
    server_index = find_prob_server(vdc.AI[1].app_type, routing_prob, feas_apps)
    println(PI.file_sim_record,"(Time: $(vdc.current_time)) Current event: New arrival ($(vdc.AI[1].arrival_index)th arrival, app_type: $(vdc.AI[1].app_type), workload: $(vdc.AI[1].remaining_workload), server_dispatched: $(server_index)")

    # Routing job and Workload increment based on the type of job and current prices of servers 
    vdc.S[server_index].previous_remaining_workload = vdc.S[server_index].current_remaining_workload  # Save previous remaining workload
    vdc.S[server_index].current_remaining_workload = vdc.S[server_index].previous_remaining_workload + vdc.AI[1].remaining_workload # Add arriving workload to current remaining workload

    # Reducing workloads
    for j in 1:length(vdc.S)   # For all server
      for i in 1:length(vdc.S[j].WIP)   # For each arrival within server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the arrival's worklaod
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the total reamining workload
      end
      # Update cumulative power consumption of server
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption
      
      #Update server speeds and prices
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      #If server is idle, set the speed as minimum as possible
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      else
        vdc.S[j].current_speed = max(vdc.SS[j].γ, ro_server_speeds[j])
      end
      vdc.S[j].previous_price = vdc.S[j].current_price
      vdc.S[j].current_price = vdc.S[j].previous_price + p_dot(j, vdc.S)
    end

    # Updating next completion time
    push!(vdc.S[server_index].WIP, vdc.AI[1]) #Add a job object to WIP of routed server
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    vdc.S[server_index].num_in_server += 1 # Update the number of jobs in server
    popfirst!(vdc.AI) # Remove the arrival from Arrival Information
    vdc.next_arrival = vdc.AI[1].arrival_time
  elseif vdc.next_completion == min(vdc.next_regular_update, vdc.next_arrival, vdc.next_completion)
    #If next update is due to completion
    server_index = vdc.next_completion_info["server_num"]
    WIP_index = vdc.next_completion_info["WIP_num"]
    inter_event_time = vdc.next_completion - vdc.current_time
    vdc.current_time = vdc.next_completion
    println(PI.file_sim_record,"(Time: $(vdc.current_time)) Current event: Completion ($(vdc.passed_arrivals+1)th, server: $server_index , server $server_index's remaining WIPs: $(length(vdc.S[server_index].WIP))")

    # for summarizing
    if vdc.warmed_up == true
      sojourn_time = vdc.current_time - vdc.S[server_index].WIP[WIP_index].arrival_time
      if sojourn_time > vdc.SS[server_index].δ
        push!(PI.sojourn_time_violation_array[server_index], 1)
      else
        push!(PI.sojourn_time_violation_array[server_index], 0)
      end

      push!(PI.sojourn_time_array[server_index], sojourn_time)
    end

    vdc.S[server_index].previous_remaining_workload = vdc.S[server_index].current_remaining_workload  # Save the remaining workload before update

    for j in 1:length(vdc.S)   # For all servers
      for i in 1:length(vdc.S[j].WIP)   # For all arrivals within the server
        vdc.S[j].WIP[i].remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  #  Reduce the arrival's worklaod
        vdc.S[j].current_remaining_workload -= (vdc.S[j].current_speed/length(vdc.S[j].WIP))*inter_event_time  # Reduce the total reamining workload
      end
      # Update cumulative power consumption of server
      consumption = inter_event_time*server_power(j,vdc.SS, vdc.S)
      vdc.S[j].cumulative_power_consumption += consumption
      vdc.total_cumulative_power_consumption += consumption
      
      #Update server speeds and prices
      vdc.S[j].previous_speed = vdc.S[j].current_speed
      if round(vdc.S[j].current_remaining_workload, digits = 2) == 0.00
        vdc.S[j].current_speed = vdc.SS[j].γ
      else
        vdc.S[j].current_speed = max(vdc.SS[j].γ, ro_server_speeds[j])
      end
      vdc.S[j].previous_price = vdc.S[j].current_price
      vdc.S[j].current_price = vdc.S[j].previous_price + p_dot(j, vdc.S)
    end

    # Remove the completed job
    deleteat!(vdc.S[server_index].WIP, WIP_index)
    vdc.S[server_index].num_in_server -= 1 # Substitue 1 form number of jobs in server

    # Updating next completion time
    server_index_2 = 0
    WIP_index = 0
    shortest_remaining_time = typemax(Float64)

    for j in 1:length(vdc.S)
      for i in 1:length(vdc.S[j].WIP)
        if shortest_remaining_time > (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          shortest_remaining_time = (vdc.S[j].WIP[i].remaining_workload/(vdc.S[j].current_speed/length(vdc.S[j].WIP)))
          WIP_index = i
          server_index_2 = j
          vdc.next_completion = vdc.current_time + shortest_remaining_time
          vdc.next_completion_info = Dict("server_num"=>server_index_2, "WIP_num"=>WIP_index)
        end
      end
    end

    if server_index_2 == 0 && WIP_index == 0 # If there is no arrival within entire vdc
      vdc.next_completion = typemax(Float64)
    end
    vdc.passed_arrivals += 1
  end
end


#Functions for doing a warm-up stage
function warm_up_dynamic(vdc::VirtualDataCenter, PI::Plot_Information, WARM_UP_TIME::Float64)
  println(PI.file_sim_record, "Warming up for $(WARM_UP_TIME) times.")
  print("Doing a Warm up ")
  #j = 0
  while vdc.current_time < WARM_UP_TIME
    #Making a progress through an event
    next_event_dynamic(vdc, PI)
  end
  vdc.warmed_up = true
  println(PI.file_sim_record, "Warmed up.")
end

function warm_up_static(vdc::VirtualDataCenter, PI::Plot_Information, WARM_UP_TIME::Float64, routing_prob::Dict{Any, Any}, ro_server_speeds::Array{Float64}, feas_apps::Array{Array{Int64}})
  println(PI.file_sim_record, "Warming up for $(WARM_UP_TIME) times.")
  print("Doing a Warm up ")
  #j = 0
  while vdc.current_time < WARM_UP_TIME
    next_event_static(vdc, PI, routing_prob, ro_server_speeds, feas_apps)
    #Making a progress through an event
  end
  vdc.warmed_up = true
  println(PI.file_sim_record, "Warmed up.")
end

#Functions to run the whole simulation
function run_to_end_dynamic(vdc::VirtualDataCenter, PI::Plot_Information, REPLICATION_TIME::Float64, WARM_UP_TIME::Float64)
  if !vdc.warmed_up
    #Doing the Warm up
    warm_up_dynamic(vdc,PI,WARM_UP_TIME) 
  end
  println("-- Warm up Over ")
  i = 0
  while vdc.current_time < REPLICATION_TIME
    #Making a progress through an event
    next_event_dynamic(vdc, PI)
    i += 1
    if i % 300000 == 1
      #Checking a time
      println("Running at : ", vdc.current_time)
    end
  end
  println(PI.file_sim_record, "Simulation finished")
end

function run_to_end_static(vdc::VirtualDataCenter, PI::Plot_Information, REPLICATION_TIME::Float64, WARM_UP_TIME::Float64, routing_prob::Dict{Any, Any}, ro_server_speeds::Array{Float64}, feas_apps::Array{Array{Int64}})
  if !vdc.warmed_up
    #Doing the Warm up
    warm_up_static(vdc,PI,WARM_UP_TIME, routing_prob, ro_server_speeds, feas_apps)
  end
  println("-- Warm up Over ")
  i = 0
  while vdc.current_time < REPLICATION_TIME
    #Making a progress through an event
    next_event_static(vdc, PI, routing_prob, ro_server_speeds, feas_apps)
    i += 1
    if i % 300000 == 1
      #Checking a time
      println("Running at : ", vdc.current_time)
    end
  end
  println(PI.file_sim_record, "Simulation finished")
end

#############################Some Additional Functions###########################

#Function making workload settings
function workload_setter(λₒ, SCOVₐₒ, μₒ_inv, SCOVₛₒ, ωₒ, inter_arrival_distributions, workload_distributions)
  WS = Workload_Setting[]

  App_num = length(λₒ)
  for i in 1:App_num
    push!(WS, Workload_Setting(ωₒ[i], inter_arrival_distributions[i], 1/λₒ[i], SCOVₐₒ[i], sqrt((1/λₒ[i]^2)*SCOVₐₒ[i]), workload_distributions[i], μₒ_inv[i], SCOVₛₒ[i], sqrt((μₒ_inv[i]^2)*SCOVₛₒ[i])) )
  end
  return WS
end

#Function generating arrival informations
function arrival_generator(WS::Array{Workload_Setting}, REPLICATION_TIME::Float64) 
  # Terminating condition is either REPLICATION_TIME or MAX_ARRIVALS
  vectors = []
  for j in 1:length(WS)
    if WS[j].inter_arrival_distribution == "LogNormal"
      new_vector = rand(LogNormal(log(WS[j].mean_inter_arrival/sqrt(WS[j].scv_inter_arrival+1)), sqrt(log(WS[j].scv_inter_arrival+1))), 1)
    elseif WS[j].inter_arrival_distribution == "Exponential"
      new_vector = rand(Exponential(WS[j].mean_inter_arrival), 1)
    end
    push!(vectors, new_vector)
  end

  t = 0.0
  while t < REPLICATION_TIME + 100
    for j in 1:length(WS)
      if WS[j].inter_arrival_distribution == "LogNormal"
        push!(vectors[j], vectors[j][end] + rand(LogNormal(log(WS[j].mean_inter_arrival/sqrt(WS[j].scv_inter_arrival+1)), sqrt(log(WS[j].scv_inter_arrival+1)))))
      elseif WS[j].inter_arrival_distribution == "Exponential"
        push!(vectors[j], vectors[j][end] + rand(Exponential(WS[j].mean_inter_arrival)))
      end
    end
    temp = Inf
    for j in 1:length(WS)
      temp = min(temp, vectors[j][end])
    end
    t = temp
  end

  AI = Arrival_Information[]
  m = 0.0
  i = 1
  while m < REPLICATION_TIME + 1.0
    min_idx = 0
    arr_moment = Inf
    for j in 1:length(WS)
      if vectors[j][1] < arr_moment
        arr_moment = vectors[j][1]
        min_idx = j
      end
    end
    if WS[min_idx].workload_distribution == "LogNormal"
      push!(AI, Arrival_Information(i,min_idx,arr_moment,rand(LogNormal(log(WS[min_idx].mean_workload/sqrt(WS[min_idx].scv_workload+1)), sqrt(log(WS[min_idx].scv_workload+1)))), typemax(Float64)))
    elseif WS[min_idx].workload_distribution == "Exponential"
      push!(AI, Arrival_Information(i,min_idx,arr_moment,rand(Exponential(WS[min_idx].mean_workload)), typemax(Float64)))
    end
    i += 1
    popfirst!(vectors[min_idx])
    m = arr_moment
  end
  return AI
end

function server_setter(threshold, quantile_percentage, K, α, γs, Γs, feas_servs)
  SS = Server_Setting[]
  Server_Num = length(K)
  for i in 1:Server_Num
    push!(SS, Server_Setting(γs[i], Γs[i], K[i], α[i], 3, threshold, 1-quantile_percentage, 30.0, 100.0, Tuple(feas_servs[i])))
  end
  return SS
end

# Function creating server objects array based on server setting and workload setting
function server_creater(SS::Array{Server_Setting}, WS::Array{Workload_Setting})
  #Calculated the aggregated SCOV
  tempv = Float64[]
  for i in 1:length(WS)
    push!(tempv,1/WS[i].mean_workload)
  end
  μ_min = minimum(tempv)
  num = 0.0
  denom = 0.0
  for i in 1:length(WS)
    num += (1/WS[i].mean_inter_arrival)*(WS[i].std_inter_arrival/WS[i].mean_inter_arrival)^2
    denom += (1/WS[i].mean_inter_arrival)
  end
  agg_scv = num/denom

  #Create server object and set the initialization value
  S = Server[]
  for j in 1:length(SS)
    push!(S, Server(SS[j].x_0, SS[j].x_0, SS[j].p_0, SS[j].p_0))
    S[j].κ = (-log(SS[j].ϵ)*max(1,agg_scv))/(μ_min*SS[j].δ)
  end
  return S
end

# Function calculating standard deviations of inter-arrival time
function calculate_sigma_a(λ, SCV)
  result = []
  for i in 1:length(λ)
      push!(result, sqrt(SCV[i])/λ[i])
  end
  return result
end

# Function calculating standard deviations of workload amount
function calculate_sigma_s(μ_inv, SCV)
  result = []
  for i in 1:length(μ_inv)
      push!(result, sqrt(SCV[i])*μ_inv[i])
  end
  return result
end

# Function transforming list type routing probability into dictionary form
function calculate_prob_dict(routing_prob, apps_server_info_setting)
  prob_dict = Dict()
  for i in 1:apps_server_info_setting.I
      for j in apps_server_info_setting.feas_apps[i]
          prob_dict[i, j] = routing_prob[i,j]
      end
  end
  return prob_dict
end

################################################################################
###########################Actual Functions for Executing Simulation#######################

#################Solving an Optimization problem#################

#Calculate Routing Probability and Server Speeds (Static Control)
function calculate_routing_prob_and_server_speeds(x_start_dif, N, ϵ, δ, apps_server_info_setting, power_info_setting)
  I = apps_server_info_setting.I
  feas_servs = apps_server_info_setting.feas_servs
  J = apps_server_info_setting.J
  feas_apps = apps_server_info_setting.feas_apps

  λₒ = apps_server_info_setting.λₒ
  SCOVₐₒ = apps_server_info_setting.SCOVₐₒ
  σₐₒ = apps_server_info_setting.σₐₒ
  μₒ_inv = apps_server_info_setting.μₒ_inv
  SCOVₛₒ = apps_server_info_setting.SCOVₛₒ
  σₛₒ = apps_server_info_setting.σₛₒ
  inter_arrival_distributions = apps_server_info_setting.inter_arrival_distributions
  workload_distributions = apps_server_info_setting.workload_distributions
  ωₒ = apps_server_info_setting.ωₒ

  K, α = power_info_setting.K, power_info_setting.α
  x_mins, x_maxs =power_info_setting.γs, power_info_setting.Γs

  m = Model(Ipopt.Optimizer)
  set_optimizer_attribute(m, "tol", 1e-2)
  set_optimizer_attribute(m, "check_derivatives_for_naninf", "yes")
  set_optimizer_attribute(m, "start_with_resto", "yes")
  set_optimizer_attribute(m, "resto_failure_feasibility_threshold", 10.0)

  p_start = [1/length(feas_apps[i]) for i in 1:I]
  println("p starts with : ", p_start)
  x_start = [x_mins[j] + x_start_dif for j in 1:J]
  println("x starts with : ", x_start)

  # x (variable)
  @variable(m, x[j = 1:J] >= x_mins[j], start = x_start[j])

  #p (variable)
  @variable(m, p[i in 1:I, j in feas_apps[i]] >= 0, start = p_start[i])
  @constraint(m, prob_sum[i = 1:I], sum(p[i,j] for j in feas_apps[i]) == 1)

  #λ (variable)
  λ_start = [sum(λₒ[i]*p_start[i] for i in feas_servs[j]) for j in 1:J]
  println("λ starts with ", λ_start)
  @variable(m, λ[j = 1:J], start = λ_start[j])
  @constraint(m, λ_con[j = 1:J], λ[j] == sum(λₒ[i]*p[i, j] for i in feas_servs[j]))

  #σₐ (variable)
  σₐ_start = [sqrt(sum(p_start[i]*SCOVₐₒ[i] + (1-p_start[i]) for i in feas_servs[j]))/(λ_start[j]) for j in 1:J]
  println("σₐ starts with : ", σₐ_start)
  @variable(m, σₐ[j = 1:J] >= 0, start = σₐ_start[j])
  @NLconstraint(m, σₐ_con[j = 1:J], (λ[j]*σₐ[j])^2 == sum(p[i,j]*SCOVₐₒ[i] + (1-p[i,j]) for i in feas_servs[j]))

  #ρ (expression)
  μ_inv_start = [sum(μₒ_inv[i]*λₒ[i]*p_start[i] for i in feas_servs[j])/(x_start[j]*λ_start[j]) for j in 1:J]
  println("1/μ starts with ", μ_inv_start)
  @variable(m, μ_inv[j = 1:J], start = μ_inv_start[j])
  @NLconstraint(m, μ_inv_con[j = 1:J], μ_inv[j]*x[j]*λ[j] == sum(μₒ_inv[i]*λₒ[i]*p[i,j] for i in feas_servs[j]))

  #σₛ (variable)
  σₛ_start = [(sqrt(sum(λₒ[i]*p_start[i]*(σₛₒ[i]^2 + (μₒ_inv[i]^2)) for i in feas_servs[j])/λ_start[j] - (sum(λₒ[i]*p_start[i]*μₒ_inv[i] for i in feas_servs[j])/λ_start[j])^2))/x_start[j] for j in 1:J]
  println("σₛ starts with : ", σₛ_start)
  @variable(m, σₛ[j = 1:J] >= 0, start = σₛ_start[j])
  @NLconstraint(m, σₛ_con[j = 1:J], (λ[j]*x[j]*σₛ[j])^2 == λ[j]*sum(λₒ[i]*p[i,j]*(σₛₒ[i]^2 + (μₒ_inv[i]^2)) for i in feas_servs[j]) - sum(λₒ[i]*p[i,j]*μₒ_inv[i] for i in feas_servs[j])^2 )

  #σₛ² + x²σₐ² (expression)
  sqrt_σₛ²_plus_σₐ²_start = [sqrt(σₛ_start[j]^2 + σₐ_start[j]^2) for j in 1:J]
  println("√(σₛ²+σₐ²) starts with : ", sqrt_σₛ²_plus_σₐ²_start)
  @variable(m, sqrt_σₛ²_plus_σₐ²[j = 1:J] >= 0, start = sqrt_σₛ²_plus_σₐ²_start[j])
  @NLconstraint(m, sqrt_σₛ²_plus_σₐ²_con[j = 1:J], sqrt_σₛ²_plus_σₐ²[j]^2 == σₛ[j]^2 + σₐ[j]^2)

  function Φ(x)
      sgn = tanh(100000*x)
      ind = (sgn+1)/2
      #println("x has sign : ", sgn)
      #println("so ind : ", ind)
      abs_x = sgn*x
      nom = exp(-abs_x^2 / 2)
      denom = 0.226 + 0.64*abs_x + 0.33*sqrt(abs_x^2 + 3)
      tail_prob = (nom/denom) * (1/sqrt(2*pi))
      #return 1 - tail_prob
      return ind*(1-tail_prob) + (1-ind)*tail_prob
  end

  register(m, :Φ, 1, Φ; autodiff = true)

  @variable(m, γ_uc_r_a[n = 1:N, k = 1:n, j = 1:J])
  @variable(m, γ_uc_r_s[n = 1:N, k = 1:n, j = 1:J])
  @NLconstraint(m, γ_uc_r_con[n = 1:N, k = 1:n, j = 1:J], n*μ_inv[j] - (k-1)/λ[j] + γ_uc_r_s[n,k,j]*σₛ[j]*sqrt(n) + γ_uc_r_a[n,k,j]*σₐ[j]*sqrt(k-1) == δ)

  @variable(m, γ_uc_q_a[j = 1:J])
  @variable(m, γ_uc_q_s[j = 1:J])
  @NLconstraint(m, γ_uc_q_con[j = 1:J], (γ_uc_q_a[j]*σₐ[j] + γ_uc_q_s[j]*σₛ[j])^2 == 2*(1/λ[j] - μ_inv[j])*(δ - 2/λ[j] + μ_inv[j]))

  @variable(m, r[n = 1:N, k = 1:n, j = 1:J])
  @NLconstraint(m, r_con[n = 1:N, k = 1:n, j = 1:J], Φ(γ_uc_r_a[n, k, j])*Φ(γ_uc_r_s[n, k, j]) == 1 - r[n, k, j])

  @variable(m, q[j = 1:J])
  @NLconstraint(m, q_con[j = 1:J], Φ(γ_uc_q_a[j])*Φ(γ_uc_q_s[j]) == 1 - q[j])

  @variable(m, p_bl[n = 1:N, j = 1:J])
  @NLconstraint(m, p_bl_con[j = 1:J], p_bl[1, j] == Φ((1/λ[j] - μ_inv[j])/sqrt_σₛ²_plus_σₐ²[j]))
  @NLconstraint(m, p_bl_con2[n = 2:N, j = 1:J], p_bl[n, j] == Φ(sqrt(n)*(1/λ[j] - μ_inv[j])/sqrt_σₛ²_plus_σₐ²[j]) - Φ(sqrt(n-1)*(1/λ[j] - μ_inv[j])/sqrt_σₛ²_plus_σₐ²[j]))

  @NLconstraint(m, SLA[j = 1:J], sum((p_bl[n, j]/n) * sum(r[n, k, j] for k in 1:n) for n in 1:N) + q[j]*(1-sum(p_bl[n, j] for n in 1:N)) <= ϵ)

  @NLobjective(m, Min, sum(λ[j]*μ_inv[j]*α[j]*(x[j]^3 - x_mins[j]^3) + K[j] + α[j]*(x_mins[j]^3) for j in 1:J))

  JuMP.optimize!(m)
  objective_value = JuMP.objective_value(m) 
  routing_prob = JuMP.value.(p)
  ro_server_speeds = JuMP.value.(x)

  println("Objective Value : ", objective_value)

  println("x : ", JuMP.value.(x))
  println("P : ", JuMP.value.(p))

  return routing_prob, ro_server_speeds
end

#################Running a Simulation ###########################

#Execute simulation with dynamic control policy
function calculate_dynamic_results(threshold, quantile_percentage, apps_server_info_setting, power_info_setting)
  λₒ, SCOVₐₒ, μₒ_inv, SCOVₛₒ, ωₒ, feas_servs, inter_arrival_distributions, workload_distributions = apps_server_info_setting.λₒ, apps_server_info_setting.SCOVₐₒ, apps_server_info_setting.μₒ_inv, apps_server_info_setting.SCOVₛₒ, apps_server_info_setting.ωₒ, apps_server_info_setting.feas_servs, apps_server_info_setting.inter_arrival_distributions, apps_server_info_setting.workload_distributions
  K, α, γs, Γs = power_info_setting.K, power_info_setting.α, power_info_setting.γs, power_info_setting.Γs

  file_sim_record = open("sim_record_dynamic.txt" , "w")
  file_summarization = open("summarization_dynamic.txt" , "w")
  WS = workload_setter(λₒ, SCOVₐₒ, μₒ_inv, SCOVₛₒ, ωₒ, inter_arrival_distributions, workload_distributions)
  SS = server_setter(threshold, quantile_percentage, K, α, γs, Γs, feas_servs)
  S = server_creater(SS,WS)
  AI = arrival_generator(WS,REPLICATION_TIME)
  vdc = VirtualDataCenter(WS, AI, SS, WARM_UP_ARRIVALS, MAX_ARRIVALS, WARM_UP_TIME, REPLICATION_TIME, REGULAR_UPDATE_INTERVAL, S)
  PI = Plot_Information(S,file_sim_record,file_summarization)
  run_to_end_dynamic(vdc, PI, REPLICATION_TIME, WARM_UP_TIME)

  # Write summarization
  println(file_summarization, "Total Cumulative Power Consumption: $(vdc.total_cumulative_power_consumption)")
  println(file_summarization, " ")
  println(file_summarization, "Power consumption/Unit Time : $(vdc.total_cumulative_power_consumption/REPLICATION_TIME)")
  println(file_summarization, " ")
  for j = 1:length(S)
  println(file_summarization, "P[W_$j>=δ_$j]: $(sum(PI.sojourn_time_violation_array[j])/length(PI.sojourn_time_array[j]))")
  end
  println(file_summarization, " ")
  average_speeds = [sum([PI.speed_array[j][i]*(PI.time_array[i+1]-PI.time_array[i]) for i in 1:length(PI.time_array)-1])/PI.time_array[end] for j in 1:10]
  for j in 1:length(S)
  println(file_summarization, "Average Speed of Server $j: $(average_speeds[j])")
  end
  println(file_summarization, " ")
  for j in 1:length(S)
  println(file_summarization, "E[W_$j]: $(sum(PI.sojourn_time_array[j])/length(PI.sojourn_time_array[j]))")
  end
  println(file_summarization, " ")
  println(file_summarization, "The number of jobs completed")
  for j in 1:length(S)
  println(file_summarization, "Server $j: $(length(PI.sojourn_time_array[j]))")
  end

  close(file_summarization)
  close(file_sim_record)
  println("-- Simulation Finished (Dynamic)!")
  power_per_unit = vdc.total_cumulative_power_consumption/REPLICATION_TIME
  violation_probs = [sum(PI.sojourn_time_violation_array[i])/length(PI.sojourn_time_array[i]) for i in 1:length(SS)]
  return power_per_unit, violation_probs
end

#Execute simulation with static policy
function calculate_static_results(threshold, quantile_percentage, routing_prob, ro_server_speeds, apps_server_info_setting, power_info_setting)
  λₒ, SCOVₐₒ, μₒ_inv, SCOVₛₒ, ωₒ, feas_servs, feas_apps, inter_arrival_distributions, workload_distributions = apps_server_info_setting.λₒ, apps_server_info_setting.SCOVₐₒ, apps_server_info_setting.μₒ_inv, apps_server_info_setting.SCOVₛₒ, apps_server_info_setting.ωₒ, apps_server_info_setting.feas_servs, apps_server_info_setting.feas_apps, apps_server_info_setting.inter_arrival_distributions, apps_server_info_setting.workload_distributions
  K, α, γs, Γs = power_info_setting.K, power_info_setting.α, power_info_setting.γs, power_info_setting.Γs

  file_sim_record = open("sim_record_static.txt" , "w")
  file_summarization = open("summarization_static.txt" , "w")
  WS = workload_setter(λₒ, SCOVₐₒ, μₒ_inv, SCOVₛₒ, ωₒ, inter_arrival_distributions, workload_distributions)
  SS = server_setter(threshold, quantile_percentage, K, α, γs, Γs, feas_servs)
  S = server_creater(SS,WS)
  AI = arrival_generator(WS,REPLICATION_TIME)
  vdc = VirtualDataCenter(WS, AI, SS, WARM_UP_ARRIVALS, MAX_ARRIVALS, WARM_UP_TIME, REPLICATION_TIME, REGULAR_UPDATE_INTERVAL, S)
  PI = Plot_Information(S,file_sim_record,file_summarization)
  run_to_end_static(vdc, PI, REPLICATION_TIME, WARM_UP_TIME, routing_prob, ro_server_speeds, feas_apps)

  println(file_summarization, "Total Cumulative Power Consumption: $(vdc.total_cumulative_power_consumption)")
  println(file_summarization, " ")
  println(file_summarization, "Power consumption/Unit Time : $(vdc.total_cumulative_power_consumption/REPLICATION_TIME)")
  println(file_summarization, " ")
  for j = 1:length(S)
    println(file_summarization, "P[W_$j>=δ_$j]: $(sum(PI.sojourn_time_violation_array[j])/length(PI.sojourn_time_array[j]))")
  end
  println(file_summarization, " ")
  average_speeds = [sum([PI.speed_array[j][i]*(PI.time_array[i+1]-PI.time_array[i]) for i in 1:length(PI.time_array)-1])/PI.time_array[end] for j in 1:10]
  for j in 1:length(S)
    println(file_summarization, "Average Speed of Server $j: $(average_speeds[j])")
  end
  println(file_summarization, " ")
  for j in 1:length(S)
    println(file_summarization, "E[W_$j]: $(sum(PI.sojourn_time_array[j])/length(PI.sojourn_time_array[j]))")
  end
  println(file_summarization, " ")
  println(file_summarization, "The number of jobs completed")
  for j in 1:length(S)
    println(file_summarization, "Server $j: $(length(PI.sojourn_time_array[j]))")
  end

  close(file_summarization)
  close(file_sim_record)
  println("-- Simulation Finished (Static)")
  power_per_unit = vdc.total_cumulative_power_consumption/REPLICATION_TIME
  violation_probs = [sum(PI.sojourn_time_violation_array[i])/length(PI.sojourn_time_array[i]) for i in 1:length(SS)]
  return power_per_unit, violation_probs
end

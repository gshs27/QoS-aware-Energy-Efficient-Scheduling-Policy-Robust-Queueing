
##################################################################
################ Quantile Fitting Functions ######################
using Distributions, Printf, PyPlot
using GLM, DataFrames
using QuantReg

############ Common Functions
mutable struct JOB_for_Fitting
    arrival_index::Int64
    arrival_time::Float64
    remaining_workload::Float64
    completion_time::Float64
    sojorun_time::Float64
end

function calculate_sojourn_time_quantile(finished_jobs, ε)
    sojourn_times_list = [finished_job.sojorun_time for finished_job in finished_jobs]
    sort!(sojourn_times_list)
    idx = Int64(floor(length(finished_jobs)*(1-ε)))
    return sojourn_times_list[idx]
end

############ Exponential

function append_arrivals_and_workloads_exponential(n, μ, λ, arrival_times, workloads)
    inter_arrival_times = rand(Distributions.Exponential(1/λ), n)
    new_workloads = rand(Distributions.Exponential(1/μ), n)
    for i in 1:length(inter_arrival_times)
        push!(arrival_times, arrival_times[length(arrival_times)] + inter_arrival_times[i])
    end
    for i in 1:length(new_workloads)
        push!(workloads, new_workloads[i])
    end
    return arrival_times, workloads
end

function simulate_exponential(n, μ, λ, warm_up_bool, warm_up_time)
    current_time = 0.0
    arrival_index = 1
    arrival_times = [rand(Distributions.Exponential(1/λ))]
    workloads = [rand(Distributions.Exponential(1/μ))]
    last_completion = 0

    current_time = arrival_times[1]
    jobs = [JOB_for_Fitting(1, current_time, workloads[1], current_time + workloads[1], 0)]

    arrival_times, workloads = append_arrivals_and_workloads_exponential(n-1, μ, λ, arrival_times, workloads)
    
    popfirst!(arrival_times)
    popfirst!(workloads)

    n_jobs = length(jobs)
    finished_jobs = []
    
    #println("Initialized")
    #println("Initialization Info --------")
    #println("Current Time : ", current_time)
    #println("Number of jobs : ", n_jobs)
    #println("Job Info : ", jobs[1])
    #println("Arrival Info : ", arrival_times[1:10])
    #println("Workload Info : ", workloads[1:10])
    
    while length(finished_jobs) != n

        if length(arrival_times) < 100
            arrival_times, workloads = append_arrivals_and_workloads_exponential(100, μ, λ, arrival_times, workloads)
        end
        
        next_arrival = arrival_times[1]
        next_completion = Inf
        next_completion_job_ind = 0

        for i in 1:n_jobs
            job = jobs[i]
            if job.completion_time < next_completion
                next_completion_job_ind = i
                next_completion = job.completion_time
            end
        end
        
        if next_arrival < next_completion

            for job in jobs
                job.remaining_workload -= (next_arrival - current_time) / n_jobs
                job.completion_time = next_arrival + job.remaining_workload * (n_jobs + 1)
            end
            arrival_index += 1
            push!(jobs, JOB_for_Fitting(arrival_index, next_arrival, workloads[1], next_arrival + (workloads[1] * (n_jobs + 1)), 0))
            popfirst!(arrival_times)
            popfirst!(workloads)
            current_time = next_arrival

            n_jobs += 1
        elseif  next_completion < next_arrival

            finished_job = jobs[next_completion_job_ind]
            deleteat!(jobs, next_completion_job_ind)
            for job in jobs
                job.remaining_workload -= (next_completion - current_time) / n_jobs
                job.completion_time = next_completion + job.remaining_workload * (n_jobs - 1)
            end
            n_jobs -= 1
            current_time = next_completion
            last_completion = current_time
            finished_job.sojorun_time = finished_job.completion_time - finished_job.arrival_time
            if warm_up_bool == true
                if current_time > warm_up_time
                    push!(finished_jobs, finished_job)
                end
            else
                push!(finished_jobs, finished_job)
            end
        end
    end
    return finished_jobs
end

function generate_params_list_exponential(ρ_candidates, λ₀, λ_μ_scaling_factors)
    params_list = []
    for ρ in ρ_candidates
        #Here λ₀, μ₀ are baselines ρ = λ₀/μ₀
        μ₀ = λ₀/ρ
        for scaling_factor in λ_μ_scaling_factors
            λ = scaling_factor * λ₀
            μ = scaling_factor * μ₀
            σₐ, σₛ = 1/λ, 1/μ
            push!(params_list, [ρ, σₐ, σₛ])
        end
    end
    return params_list
end

function calculate_y_exponential(n, μ, λ, ε)
    finished_jobs = simulate_exponential(n, μ, λ, 1, 10000) #Warmup Enabled (for time 10000.0)
    S_quantile = calculate_sojourn_time_quantile(finished_jobs, ε)
    ρ = λ/μ
    σₐ, σₛ = 1/λ, 1/μ
    y = (S_quantile - (2-ρ)/λ)*2*(1-ρ)/λ
    #@printf("----Simulation with (ρ, λ, σₐ, μ, σₛ) = (%.2f, %.2f, %.2f, %.2f, %.2f)-----", ρ, λ, σₐ, μ, σₛ)
    #println()
    #@printf("S_UB = %.2f, (2-ρ)/λ = %.2f, 2(1-ρ)/λ = %.2f, y = %.2f -----", S_ub, (2-ρ)/λ, 2*(1-ρ)/λ, y)
    #println()
    return y, S_quantile
end

function calculate_y_list_exponential(params_list_exponential, n, ε)
    progress_check = Int64(floor(length(params_list_exponential)/10))
    println("Total ", length(params_list_exponential), " parameter lists to check")
    y_list = []
    S_quantile_list = []
    for i in 1:length(params_list_exponential)
        if i % progress_check == 0
            println("---", 10*(i/progress_check), "%---")
        end
        params = params_list_exponential[i]
        ρ, σₐ, σₛ = params
        #println("params : ", params)
        λ, μ = 1/σₐ, 1/σₛ
        y, S_quantile = calculate_y_exponential(n, μ, λ, ε)
        append!(y_list, y)
        append!(S_quantile_list, S_quantile)
    end
    return y_list, S_quantile_list
end

function create_data_exponential(params_list_exponential, y_list_exponential, S_quantile_list)
    data_exponential = DataFrame(σₛ²_over_ρ = Float64[], ρσₐ² = Float64[], ρ_term3 = Float64[], y = Float64[])
    y_list_to_use = []
    params_list_to_use = []
    S_quantile_to_use_list = []
    for i in 1:length(y_list_exponential)
        ρ, σₐ, σₛ = params_list_exponential[i]
        λ = 1/σₐ
        y = y_list_exponential[i]
        if y > 0
            push!(params_list_to_use, params_list_exponential[i])
            push!(data_exponential, [(σₛ^2)/ρ, ρ*(σₐ^2), 2*(1-ρ)*(2-ρ)/(λ^2), y])
            push!(y_list_to_use, y)
            push!(S_quantile_to_use_list, S_quantile_list[i])
        end
    end
    return data_exponential, y_list_to_use, params_list_to_use, S_quantile_to_use_list
end

############ LogNormal

function append_arrivals_and_workloads_lognormal(n, λ, SCOV_a, μ, SCOV_s, arrival_times, workloads)
    inter_arrival_times = rand(LogNormal(log((1/λ)/sqrt(SCOV_a+1)), sqrt(log(SCOV_a+1))))
    new_workloads = rand(LogNormal(log((1/μ)/sqrt(SCOV_s+1)), sqrt(log(SCOV_s+1))))
    for i in 1:length(inter_arrival_times)
        push!(arrival_times, arrival_times[length(arrival_times)] + inter_arrival_times[i])
    end
    for i in 1:length(new_workloads)
        push!(workloads, new_workloads[i])
    end
    return arrival_times, workloads
end

function simulate_lognormal(n, λ, SCOV_a, μ, SCOV_s, warm_up_bool, warm_up_time)
    current_time = 0.0
    arrival_index = 1
    arrival_times = [rand(LogNormal(log((1/λ)/sqrt(SCOV_a+1)), sqrt(log(SCOV_a+1))))]
    workloads = [rand(LogNormal(log((1/μ)/sqrt(SCOV_s+1)), sqrt(log(SCOV_s+1))))]
    last_completion = 0

    current_time = arrival_times[1]
    jobs = [JOB_for_Fitting(1, current_time, workloads[1], current_time + workloads[1], 0)]

    arrival_times, workloads = append_arrivals_and_workloads_lognormal(n-1, λ, SCOV_a, μ, SCOV_s, arrival_times, workloads)

    popfirst!(arrival_times)
    popfirst!(workloads)

    n_jobs = length(jobs)
    finished_jobs = []

    #println("Initialized")
    #println("Initialization Info --------")
    #println("Current Time : ", current_time)
    #println("Number of jobs : ", n_jobs)
    #println("Job Info : ", jobs[1])
    #println("Arrival Info : ", arrival_times[1:10])
    #println("Workload Info : ", workloads[1:10])

    while length(finished_jobs) != n

        if length(arrival_times) < 100
            arrival_times, workloads = append_arrivals_and_workloads_lognormal(100, λ, SCOV_a, μ, SCOV_s, arrival_times, workloads)
        end

        next_arrival = arrival_times[1]
        next_completion = Inf
        next_completion_job_ind = 0

        for i in 1:n_jobs
            job = jobs[i]
            if job.completion_time < next_completion
                next_completion_job_ind = i
                next_completion = job.completion_time
            end
        end

        if next_arrival < next_completion

            for job in jobs
                job.remaining_workload -= (next_arrival - current_time) / n_jobs
                job.completion_time = next_arrival + job.remaining_workload * (n_jobs + 1)
            end
            arrival_index += 1
            push!(jobs, JOB_for_Fitting(arrival_index, next_arrival, workloads[1], next_arrival + (workloads[1] * (n_jobs + 1)), 0.0))
            popfirst!(arrival_times)
            popfirst!(workloads)
            current_time = next_arrival

            n_jobs += 1
        elseif  next_completion < next_arrival

            finished_job = jobs[next_completion_job_ind]
            deleteat!(jobs, next_completion_job_ind)
            for job in jobs
                job.remaining_workload -= (next_completion - current_time) / n_jobs
                job.completion_time = next_completion + job.remaining_workload * (n_jobs - 1)
            end
            n_jobs -= 1
            current_time = next_completion
            last_completion = current_time
            finished_job.sojorun_time = finished_job.completion_time - finished_job.arrival_time
            if warm_up_bool == true
                if current_time > warm_up_time
                    push!(finished_jobs, finished_job)
                end
            else
                push!(finished_jobs, finished_job)
            end
        end
    end
    return finished_jobs
end

function generate_params_list_lognormal(ρ_candidates_lognormal, λ₀_lognormal, λ_μ_scaling_factors_lognormal, SCOV_a_list_lognormal, SCOV_s_list_lognormal)
    params_list = []
    for ρ in ρ_candidates_lognormal
        μ₀_lognormal = λ₀_lognormal/ρ
        for scaling_factor in λ_μ_scaling_factors_lognormal
            λ = scaling_factor * λ₀_lognormal
            μ = scaling_factor * μ₀_lognormal
            for SCOV_a in SCOV_a_list_lognormal
                for SCOV_s in SCOV_s_list_lognormal
                    push!(params_list, [ρ, λ, SCOV_a, μ, SCOV_s])
                end
            end
        end
    end
    return params_list
end

function calculate_y_lognormal(n, λ, SCOV_a, μ, SCOV_s, ε)
    finished_jobs = simulate_lognormal(n, λ, SCOV_a, μ, SCOV_s, 1, 10000) #Warmup Enabled (for time 10000.0)
    S_quantile = calculate_sojourn_time_quantile(finished_jobs, ε)
    ρ = λ/μ
    #σₐ, σₛ = sqrt(SCOV_a/(λ^2)), sqrt(SCOV_s/(μ^2))
    y = (S_quantile - (2-ρ)/λ)*2*(1-ρ)/λ
    #@printf("----Simulation with (ρ, λ, σₐ, μ, σₛ) = (%.2f, %.2f, %.2f, %.2f, %.2f)-----", ρ, λ, σₐ, μ, σₛ)
    #println()
    #@printf("S_UB = %.2f, (2-ρ)/λ = %.2f, 2(1-ρ)/λ = %.2f, y = %.2f -----", S_ub, (2-ρ)/λ, 2*(1-ρ)/λ, y)
    #println()
    return y, S_quantile
end

function calculate_y_list_lognormal(params_list, n, ε)
    y_list = []
    S_quantile_list = []
    println("Total ", length(params_list), " parameter lists to check")
    progress_check = Int64(floor(length(params_list)/10))
    for i in 1:length(params_list)
        params = params_list[i]
        if i % progress_check == 0
            println("---", 10*(i/progress_check), "%---")
        end
        ρ, λ, SCOV_a, μ, SCOV_s = params
        #println("params : ", params)
        y, S_quantile = calculate_y_lognormal(n, λ, SCOV_a, μ, SCOV_s, ε)
        append!(y_list, y)
        append!(S_quantile_list, S_quantile)
    end
    return y_list, S_quantile_list
end

function create_data_exponential(params_list_exponential, y_list_exponential, S_quantile_list, δ_range)
    data_exponential = DataFrame(σₛ²_over_ρ = Float64[], ρσₐ² = Float64[], ρ_term3 = Float64[], y = Float64[])
    y_list_to_use = []
    params_list_to_use = []
    S_quantile_to_use_list = []
    for i in 1:length(y_list_exponential)
        ρ, σₐ, σₛ = params_list_exponential[i]
        λ = 1/σₐ
        y = y_list_exponential[i]
        if y > 0
            if δ_range[1] <= S_quantile_list[i] <= δ_range[2]
                push!(params_list_to_use, params_list_exponential[i])
                push!(data_exponential, [(σₛ^2)/ρ, ρ*(σₐ^2), 2*(1-ρ)*(2-ρ)/(λ^2), y])
                push!(y_list_to_use, y)
                push!(S_quantile_to_use_list, S_quantile_list[i])
            end
        end
    end
    return data_exponential, y_list_to_use, params_list_to_use, S_quantile_to_use_list
end


############### Mixing

function create_data_exponential_lognormal_together_for_mixing(params_list_exponential, y_list_exponential, params_list_lognormal, y_list_lognormal, S_quantile_exponential, S_quantile_lognormal, δ_range)
    data_exponential_lognormal_together_for_mixing = DataFrame(σₛ²_over_ρ = Float64[], ρσₐ² = Float64[], ρ_term3 = Float64[], y = Float64[])
    y_list_to_use_exponential_lognormal_together_for_mixing = []
    params_to_use_exponential_lognormal_together_for_mixing = []
    S_quantile_to_use_exponential_lognormal_together_for_mixing = []
    for i in 1:length(y_list_exponential)
        ρ, σₐ, σₛ = params_list_exponential[i]
        λ = 1/σₐ
        y = y_list_exponential[i]
        if y > 0
            if δ_range[1] <= S_quantile_exponential[i] <= δ_range[2]
                push!(data_exponential_lognormal_together_for_mixing, [(σₛ^2)/ρ, ρ*(σₐ^2), 2*(1-ρ)*(2-ρ)/(λ^2), y])
                push!(y_list_to_use_exponential_lognormal_together_for_mixing, y)
                push!(params_to_use_exponential_lognormal_together_for_mixing, params_list_exponential[i])
                push!(S_quantile_to_use_exponential_lognormal_together_for_mixing, S_quantile_exponential[i])
            end
        end
    end

    n_exponentials = length(y_list_to_use_exponential_lognormal_together_for_mixing)

    for i in 1:length(y_list_lognormal)
        ρ, λ, SCOV_a, μ, SCOV_s = params_list_lognormal[i]
        σₐ, σₛ = sqrt(SCOV_a/(λ^2)), sqrt(SCOV_s/(μ^2))
        y = y_list_lognormal[i]
        if y > 0
            if δ_range[1] <= S_quantile_lognormal[i] <= δ_range[2]
                push!(data_exponential_lognormal_together_for_mixing, [(σₛ^2)/ρ, ρ*(σₐ^2), 2*(1-ρ)*(2-ρ)/(λ^2), y])
                push!(y_list_to_use_exponential_lognormal_together_for_mixing, y)
                push!(params_to_use_exponential_lognormal_together_for_mixing, params_list_lognormal[i])
                push!(S_quantile_to_use_exponential_lognormal_together_for_mixing, S_quantile_lognormal[i])
            end
        end
    end
    return data_exponential_lognormal_together_for_mixing, y_list_to_use_exponential_lognormal_together_for_mixing, params_to_use_exponential_lognormal_together_for_mixing, S_quantile_to_use_exponential_lognormal_together_for_mixing, n_exponentials
end

####################
function learn_gamma_coefficients(n = 10000, ε = 0.001, δ_range = [2, 4], quantile_level = 0.9)
  ############ Exponential Data Generation
  ρ_candidates_exponential = [i/100 for i in 5:50]
  λ₀_exponential = 2
  λ_μ_scaling_factors_exponential = [i/40 for i in 20:120]

  params_list_exponential_for_mixing = generate_params_list_exponential(ρ_candidates_exponential, λ₀_exponential , λ_μ_scaling_factors_exponential)

  y_list_exponential_for_mixing, S_quantile_list_exponential_for_mixing = calculate_y_list_exponential(params_list_exponential_for_mixing, n, ε)

  ############ LogNormal Data Generation
  #ρ_candidates_lognormal = [i/20 for i in 1:5]
  ρ_candidates_lognormal = [i/20 for i in 1:10]
  λ₀_lognormal = 2
  λ_μ_scaling_factors_lognormal = [i/4 for i in 2:12]
  SCOV_a_list_lognormal = [i/5 for i in 5:15] 
  SCOV_s_list_lognormal = [i/5 for i in 2:10] 
    
  params_list_lognormal_for_mixing = generate_params_list_lognormal(ρ_candidates_lognormal, λ₀_lognormal, λ_μ_scaling_factors_lognormal, SCOV_a_list_lognormal, SCOV_s_list_lognormal)

  y_list_lognormal_for_mixing, S_quantile_list_lognormal_for_mixing = calculate_y_list_lognormal(params_list_lognormal_for_mixing, n, ε)

  ############# Aggregating the Generated Data 
    
  data_exponential_lognormal_together_for_mixing, y_list_to_use_exponential_lognormal_together_for_mixing, params_to_use_exponential_lognormal_together_for_mixing, S_quantile_list_to_use_exponential_lognormal_together_for_mixing, n_exponentials =  create_data_exponential_lognormal_together_for_mixing(params_list_exponential_for_mixing, y_list_exponential_for_mixing, params_list_lognormal_for_mixing, y_list_lognormal_for_mixing, S_quantile_list_exponential_for_mixing, S_quantile_list_lognormal_for_mixing, δ_range)

  println("Exponential : ", length(y_list_exponential_for_mixing), ", LogNormal :", length(y_list_lognormal_for_mixing))
  println("Total : ", length(y_list_exponential_for_mixing) + length(y_list_lognormal_for_mixing))
  println("Selected within δ range and (y > 0)  : ", length(y_list_to_use_exponential_lognormal_together_for_mixing), " data (exponential : ", n_exponentials)

  ################################# Quantile Regression #######################################
  fm_mixing = @formula(y ~ σₛ²_over_ρ + ρσₐ² + ρ_term3)

  println("Quantile level : ", quantile_level*100, " % ")
  QuantileRegressor_mixing = QuantReg.rq(fm_mixing, data_exponential_lognormal_together_for_mixing, τ = quantile_level)
  #R_squared_mixing = r2(QuantileRegressor_mixing) #R-Squared
  #y_predict_mixing = predict(QuantileRegressor_mixing, data_exponential_lognormal_together_for_mixing)
  y_predict_mixing = QuantileRegressor_mixing.fit.yhat

  percent_errors_mixing = []
  absolute_percent_errors_mixing = []
  for i in 1:length(y_list_to_use_exponential_lognormal_together_for_mixing)
      #println("y (true) = ", y_list_to_use_lognormal[i], " <-> y (predict) =", y_predict_lognormal[i])
      append!(percent_errors_mixing, 100*(y_predict_mixing[i]-y_list_to_use_exponential_lognormal_together_for_mixing[i])/y_list_to_use_exponential_lognormal_together_for_mixing[i])
      append!(absolute_percent_errors_mixing, 100*abs(y_predict_mixing[i]-y_list_to_use_exponential_lognormal_together_for_mixing[i])/y_list_to_use_exponential_lognormal_together_for_mixing[i])
  end

  println("Difference Ratio - Percent Error : ", mean(percent_errors_mixing), "%")
  println("Absolute Difference Ratio - Percent Error : ", mean(absolute_percent_errors_mixing), "%")

  #coefs_mixing = GLM.coef(QuantileRegressor_mixing)

  S_quantile_list_to_use_exponential_lognormal_together_for_mixing
  S_predict_mixing = []

  S_percent_errors_mixing = []
  S_absolute_percent_errors_mixing = []
  for i in 1:length(y_predict_mixing)
      y_predict = y_predict_mixing[i]
      params = params_to_use_exponential_lognormal_together_for_mixing[i]
      if i <= n_exponentials
          ρ, σₐ, σₛ = params
          λ = 1/σₐ
          S_predict = y_predict*λ/(2*(1-ρ)) + (2-ρ)/λ
          append!(S_predict_mixing, S_predict)
          append!(S_percent_errors_mixing, 100*(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
          append!(S_absolute_percent_errors_mixing, 100*abs(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
      else
          ρ, λ, SCOV_a, μ, SCOV_s = params
          S_predict = y_predict*λ/(2*(1-ρ)) + (2-ρ)/λ
          append!(S_predict_mixing, S_predict)
          append!(S_percent_errors_mixing, 100*(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
          append!(S_absolute_percent_errors_mixing, 100*abs(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
      end
  end

  println("Sojourn Time Quantile : Difference Ratio (% Error) : ", mean(S_percent_errors_mixing), "%")
  println("Sojourn Time Quantile : Absolute Difference Ratio (% Error) : ", mean(S_absolute_percent_errors_mixing), "%")

  coefs_mixing = QuantileRegressor_mixing.fit.coef

  return coefs_mixing
end

function learn_gamma_coefficients_with_params_setting(params_setting, n = 10000, ε = 0.001, δ_range = [2, 4], quantile_level = 0.9)
    ############ Exponential Data Generation
    params_exponential = params_setting[1]
    ρ_candidates_exponential, λ₀_exponential , λ_μ_scaling_factors_exponential = params_exponential

    params_list_exponential_for_mixing = generate_params_list_exponential(ρ_candidates_exponential, λ₀_exponential , λ_μ_scaling_factors_exponential)

    y_list_exponential_for_mixing, S_quantile_list_exponential_for_mixing = calculate_y_list_exponential(params_list_exponential_for_mixing, n, ε)

    ############ LogNormal Data Generation
    params_lognormal = params_setting[2]
    ρ_candidates_lognormal, λ₀_lognormal, λ_μ_scaling_factors_lognormal, SCOV_a_list_lognormal, SCOV_s_list_lognormal = params_lognormal
        
    params_list_lognormal_for_mixing = generate_params_list_lognormal(ρ_candidates_lognormal, λ₀_lognormal, λ_μ_scaling_factors_lognormal, SCOV_a_list_lognormal, SCOV_s_list_lognormal)

    y_list_lognormal_for_mixing, S_quantile_list_lognormal_for_mixing = calculate_y_list_lognormal(params_list_lognormal_for_mixing, n, ε)

    ############# Aggregating the Generated Data 
        
    data_exponential_lognormal_together_for_mixing, y_list_to_use_exponential_lognormal_together_for_mixing, params_to_use_exponential_lognormal_together_for_mixing, S_quantile_list_to_use_exponential_lognormal_together_for_mixing, n_exponentials =  create_data_exponential_lognormal_together_for_mixing(params_list_exponential_for_mixing, y_list_exponential_for_mixing, params_list_lognormal_for_mixing, y_list_lognormal_for_mixing, S_quantile_list_exponential_for_mixing, S_quantile_list_lognormal_for_mixing, δ_range)

    println("Exponential : ", length(y_list_exponential_for_mixing), ", LogNormal :", length(y_list_lognormal_for_mixing))
    println("Total : ", length(y_list_exponential_for_mixing) + length(y_list_lognormal_for_mixing))
    println("Selected within δ range and (y > 0)  : ", length(y_list_to_use_exponential_lognormal_together_for_mixing), " data (exponential : ", n_exponentials)

    ################################# Quantile Regression #######################################
    fm_mixing = @formula(y ~ σₛ²_over_ρ + ρσₐ² + ρ_term3)

    println("Quantile level : ", quantile_level*100, " % ")
    QuantileRegressor_mixing = QuantReg.rq(fm_mixing, data_exponential_lognormal_together_for_mixing, τ = quantile_level)
    #R_squared_mixing = r2(QuantileRegressor_mixing) #R-Squared
    #y_predict_mixing = predict(QuantileRegressor_mixing, data_exponential_lognormal_together_for_mixing)
    y_predict_mixing = QuantileRegressor_mixing.fit.yhat

    percent_errors_mixing = []
    absolute_percent_errors_mixing = []
    for i in 1:length(y_list_to_use_exponential_lognormal_together_for_mixing)
        #println("y (true) = ", y_list_to_use_lognormal[i], " <-> y (predict) =", y_predict_lognormal[i])
        append!(percent_errors_mixing, 100*(y_predict_mixing[i]-y_list_to_use_exponential_lognormal_together_for_mixing[i])/y_list_to_use_exponential_lognormal_together_for_mixing[i])
        append!(absolute_percent_errors_mixing, 100*abs(y_predict_mixing[i]-y_list_to_use_exponential_lognormal_together_for_mixing[i])/y_list_to_use_exponential_lognormal_together_for_mixing[i])
    end

    println("Difference Ratio - Percent Error : ", mean(percent_errors_mixing), "%")
    println("Absolute Difference Ratio - Percent Error : ", mean(absolute_percent_errors_mixing), "%")

    #coefs_mixing = GLM.coef(QuantileRegressor_mixing)

    S_quantile_list_to_use_exponential_lognormal_together_for_mixing
    S_predict_mixing = []

    S_percent_errors_mixing = []
    S_absolute_percent_errors_mixing = []
    for i in 1:length(y_predict_mixing)
        y_predict = y_predict_mixing[i]
        params = params_to_use_exponential_lognormal_together_for_mixing[i]
        if i <= n_exponentials
            ρ, σₐ, σₛ = params
            λ = 1/σₐ
            S_predict = y_predict*λ/(2*(1-ρ)) + (2-ρ)/λ
            append!(S_predict_mixing, S_predict)
            append!(S_percent_errors_mixing, 100*(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
            append!(S_absolute_percent_errors_mixing, 100*abs(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
        else
            ρ, λ, SCOV_a, μ, SCOV_s = params
            S_predict = y_predict*λ/(2*(1-ρ)) + (2-ρ)/λ
            append!(S_predict_mixing, S_predict)
            append!(S_percent_errors_mixing, 100*(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
            append!(S_absolute_percent_errors_mixing, 100*abs(S_predict-S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])/S_quantile_list_to_use_exponential_lognormal_together_for_mixing[i])
        end
    end

    println("Sojourn Time Quantile : Difference Ratio (% Error) : ", mean(S_percent_errors_mixing), "%")
    println("Sojourn Time Quantile : Absolute Difference Ratio (% Error) : ", mean(S_absolute_percent_errors_mixing), "%")

    coefs_mixing = QuantileRegressor_mixing.fit.coef

    return coefs_mixing
end

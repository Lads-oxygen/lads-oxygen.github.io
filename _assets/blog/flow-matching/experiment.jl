module MoonFlows

using Random, LinearAlgebra, Statistics
using Lux, Optimisers, Zygote, JSON
using ForwardDiff: derivative
using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase: ODEProblem, solve, successful_retcode

function moons(rng, n; noise=0.07f0)
    angle = Float32(pi) .* rand(rng, Float32, n)
    upper = rand(rng, Bool, n)
    x = ifelse.(upper, cos.(angle), 1f0 .- cos.(angle)) .- 0.5f0
    y = ifelse.(upper, sin.(angle), 0.5f0 .- sin.(angle)) .- 0.25f0
    return permutedims(hcat(x, y)) .+ noise .* randn(rng, Float32, 2, n)
end

function entropic_pair_cdf(source, target, epsilon)
    isfinite(epsilon) && epsilon > 0 || throw(ArgumentError("OT epsilon must be positive and finite"))
    # Each column corresponds to one source point. Shifting its costs by a
    # constant preserves the coupling and keeps at least one entry nonzero.
    kernel = [sum(abs2, Float64(source[k, i]) - target[k, j] for k in axes(source, 1))
              for j in axes(target, 2), i in axes(source, 2)]
    kernel .-= minimum(kernel; dims=1)
    kernel .= exp.(-kernel ./ epsilon)
    source_scale = ones(size(source, 2))
    target_scale = ones(size(target, 2))
    source_sums = similar(source_scale)
    # Both datasets have the same size and uniform weights. Scale the plan
    # to unit row and column sums before forming the conditional CDFs.
    for iteration in 1:600
        mul!(source_scale, transpose(kernel), target_scale)
        source_scale .= inv.(source_scale)
        mul!(target_scale, kernel, source_scale)
        target_scale .= inv.(target_scale)
        iteration % 20 == 0 || continue
        mul!(source_sums, transpose(kernel), target_scale)
        marginal_error = maximum(abs, source_scale .* source_sums .- 1)
        if marginal_error < 0.001
            # The source scale cancels when normalising each column.
            kernel .*= target_scale
            accumulate!(+, kernel, kernel; dims=1)
            return kernel
        end
    end
    error("Sinkhorn did not converge. Try a larger OT epsilon.")
end

function draw_partner(cdf, i, rng)
    column = view(cdf, :, i)
    return searchsortedlast(column, rand(rng) * last(column)) + 1
end

mlp(input, width) = Chain(Dense(input => width, tanh), Dense(width => width, tanh),
                          Dense(width => width, tanh), Dense(width => 2))

function train(batch; steps, width, input, seed)
    model = mlp(input, width)
    parameters, state = Lux.setup(MersenneTwister(seed), model)
    optimiser = Optimisers.setup(Adam(0.001f0), parameters)
    for _ in 1:steps
        x, target = batch()
        gradients = Zygote.gradient(parameters) do parameters
            predicted, _ = model(x, parameters, state)
            mean(abs2, predicted .- target)
        end
        optimiser, parameters = Optimisers.update!(optimiser, parameters, only(gradients))
    end
    parameters64 = Lux.f64(parameters)
    return x -> first(model(x, parameters64, state))
end

function fit_meanflow(; steps, width, batch_size, seed)
    rng = MersenneTwister(seed + 1)
    model = mlp(4, width)
    parameters, state = Lux.setup(MersenneTwister(seed), model)
    optimiser = Optimisers.setup(Adam(0.001f0), parameters)

    for _ in 1:steps
        x0 = randn(rng, Float32, 2, batch_size)
        velocity = moons(rng, batch_size) .- x0
        a = rand(rng, Float32, 1, batch_size)
        b = rand(rng, Float32, 1, batch_size)
        s = min.(a, b)
        t = ifelse.(rand(rng, Float32, 1, batch_size) .< 0.25f0, s, max.(a, b))
        x = vcat(x0 .+ s .* velocity, s, t)
        direction = vcat(velocity, ones(Float32, 1, batch_size), zeros(Float32, 1, batch_size))
        # Forward-mode derivative on the line x + ε direction gives the JVP.
        # Computing the target outside Zygote stops gradients through the JVP.
        jvp = derivative(ε -> first(model(x .+ ε .* direction, parameters, state)), 0f0)
        target = velocity .+ (t .- s) .* jvp
        gradients = Zygote.gradient(parameters) do parameters
            predicted, _ = model(x, parameters, state)
            residual = sum(abs2, predicted .- target; dims=1)
            weight = Zygote.dropgrad(inv.(sqrt.(residual .+ 0.001f0)))
            mean(weight .* residual)
        end
        optimiser, parameters = Optimisers.update!(optimiser, parameters, only(gradients))
    end

    parameters64 = Lux.f64(parameters)
    return (x, s, t) -> first(model(vcat(x, fill(s, 1, size(x, 2)), fill(t, 1, size(x, 2))),
                                    parameters64, state))
end

function fit_field(source, target, cdf; steps, width, batch_size, seed)
    rng = MersenneTwister(seed + 1)
    pair_rng = MersenneTwister(seed + 4)
    function batch()
        ix = rand(rng, axes(source, 2), batch_size)
        iy = rand(rng, axes(target, 2), batch_size)
        x0 = source[:, ix]
        partners = isnothing(cdf) ? iy : [draw_partner(cdf, i, pair_rng) for i in ix]
        t = rand(rng, Float32, 1, batch_size)
        displacement = target[:, partners] .- x0
        return vcat(x0 .+ t .* displacement, t), displacement
    end
    model = train(batch; steps, width, input=3, seed)
    return (x, t) -> model(vcat(x, fill(t, 1, size(x, 2))))
end

function reference(field, x, times; tolerance=1e-9)
    problem = ODEProblem((x, _, t) -> field(x, t), x, (0.0, 1.0))
    result = solve(problem, Tsit5(); abstol=tolerance, reltol=tolerance,
                   saveat=times, save_start=(0.0 in times))
    successful_retcode(result) || error("Reference solve failed: $(result.retcode)")
    return (states=result.u, nfe=result.stats.nf)
end

function integrate(field, x0, steps; heun=false)
    h = 1 / steps
    states = [x0]
    for i in 0:steps-1
        x = last(states)
        t = i * h
        v = field(x, t)
        predictor = x + h * v
        next = heun ? x + (h / 2) * (v + field(predictor, (i + 1) * h)) : predictor
        push!(states, next)
    end
    return states
end

function sliced_wasserstein(x, y, directions)
    px = directions * x
    py = directions * y
    return sqrt(mean(abs2, sort(px; dims=2) .- sort(py; dims=2)))
end

function run_experiment(; seed=2026, steps=6000, student_steps=6000, meanflow_steps=6000, width=64,
                        batch_size=64, n_train=2048, ot_epsilon=0.2, n_eval=2048, n_teacher=16384)
    BLAS.set_num_threads(1)
    n_train > 0 || throw(ArgumentError("n_train must be positive"))
    rng_train = MersenneTwister(seed + 3)
    source = randn(rng_train, Float32, 2, n_train)
    target = moons(rng_train, n_train)
    println("Computing the full entropic OT coupling")
    entropic_pair_cdf(source[:, 1:1], target[:, 1:1], ot_epsilon)
    ot = @timed entropic_pair_cdf(source, target, ot_epsilon)
    rng = MersenneTwister(seed + 2)
    x_eval = randn(rng, 2, n_eval)
    held_out = Float64.(moons(rng, n_eval))
    held_out_repeat = Float64.(moons(rng, n_eval))
    angles = 2pi .* rand(rng, 128)
    directions = hcat(cos.(angles), sin.(angles))
    times = collect(range(0, 1; length=51))
    budgets = [1, 2, 4, 8, 16, 32]
    n_plot = min(n_eval, 300)
    n_paths = min(n_eval, 12)
    xy(x) = [round.(row; digits=5) for row in eachrow(x)]
    path(states) = [xy(x[:, 1:n_paths]) for x in states]
    endpoint(x) = xy(x[:, 1:n_plot])
    metric(x) = Dict("sw2" => sliced_wasserstein(x, held_out, directions))
    models = Dict{String,Any}()
    fields = Dict{String,Any}()
    # Use the same source points for both sets of training paths.
    rng_paths = MersenneTwister(seed + 8)
    path_indices = rand(rng_paths, axes(source, 2), n_paths)
    x_start = source[:, path_indices]
    independent_partners = rand(rng_paths, axes(target, 2), n_paths)
    ot_partners = [draw_partner(ot.value, i, rng_paths) for i in path_indices]
    for (name, cdf, partners) in (("independent", nothing, independent_partners),
                                  ("ot", ot.value, ot_partners))
        println("Training ", name)
        fit_field(source, target, cdf; steps=1, width, batch_size, seed)
        training = @timed fit_field(source, target, cdf; steps, width, batch_size, seed)
        field = fields[name] = training.value
        ref = reference(field, x_eval, times)
        y_train = target[:, partners]
        segments = [(1-t) .* x_start + t .* y_train for t in times]
        # In the explorer, start the integrated trajectories at the training
        # segments' initial points. The sampler comparison uses x_eval instead.
        explorer = reference(field, Float64.(x_start[:, 1:n_paths]), times)
        comparisons = Dict{Int,Any}()
        for budget in budgets
            comparisons[budget] = methods = Dict{String,Any}()
            for (method, count) in (("euler", budget), ("heun", budget ÷ 2))
                count == 0 && continue
                states = integrate(field, x_eval, count; heun=method == "heun")
                methods[method] = Dict("path" => path(states),
                    "endpoint" => endpoint(last(states)), "metric" => metric(last(states)))
            end
        end
        models[name] = Dict("segments" => path(segments), "integrated" => path(explorer.states),
            "reference" => Dict("path" => path(ref.states), "endpoint" => endpoint(last(ref.states)),
                                "metric" => metric(last(ref.states)), "nfe" => ref.nfe),
            "budgets" => comparisons, "train_seconds" => training.time)
    end

    println("Generating distillation targets with the entropic OT teacher")
    rng_teacher = MersenneTwister(seed + 4)
    x_teacher = randn(rng_teacher, 2, n_teacher)
    # Use batches to keep intermediate solver arrays small. Count calls on each
    # batch and weight them by its size to get total pointwise evaluations.
    targets = @timed begin
        y_teacher = similar(x_teacher)
        calls = 0
        point_calls = 0
        for first_col in 1:1024:n_teacher
            cols = first_col:min(first_col + 1023, n_teacher)
            solved = reference(fields["ot"], x_teacher[:, cols], [1.0])
            y_teacher[:, cols] = last(solved.states)
            calls += solved.nfe
            point_calls += length(cols) * solved.nfe
        end
        (; y_teacher, calls, point_calls)
    end
    function distillation_batches()
        rng_batches = MersenneTwister(seed + 5)
        return () -> begin
            indices = rand(rng_batches, 1:n_teacher, batch_size)
            Float32.(x_teacher[:, indices]),
            Float32.(targets.value.y_teacher[:, indices] - x_teacher[:, indices])
        end
    end
    println("Training the endpoint student")
    train(distillation_batches(); steps=1, width, input=2, seed=seed + 6)
    student = @timed train(distillation_batches(); steps=student_steps, width, input=2, seed=seed + 6)
    student_end = x_eval + student.value(x_eval)

    println("Training MeanFlow from scratch")
    fit_meanflow(; steps=1, width, batch_size, seed=seed + 7)
    meanflow = @timed fit_meanflow(; steps=meanflow_steps, width, batch_size, seed=seed + 7)
    meanflow_end = x_eval + meanflow.value(x_eval, 0.0, 1.0)
    # Query each interval [0, t] separately to show how the predicted map
    # varies with the end time. Generating samples uses only the [0, 1] call.
    starts = x_eval[:, 1:n_paths]
    meanflow_path = [starts + t .* meanflow.value(starts, 0.0, t) for t in times]
    cloud = endpoint(held_out)
    return Dict(
        "times" => times, "budgets" => budgets, "models" => models, "held_out" => cloud,
        "initial" => endpoint(x_eval), "ot_seconds" => ot.time,
        "sample_floor" => sliced_wasserstein(held_out, held_out_repeat, directions),
        "student" => Dict("teacher" => "ot", "endpoint" => endpoint(student_end),
            "metric" => metric(student_end),
            "target_seconds" => targets.time, "target_batch_calls" => targets.value.calls,
            "target_point_calls" => targets.value.point_calls, "train_seconds" => student.time),
        "meanflow" => Dict("endpoint" => endpoint(meanflow_end), "path" => path(meanflow_path),
            "metric" => metric(meanflow_end),
            "train_seconds" => meanflow.time),
        "settings" => Dict("seed" => seed, "steps" => steps, "student_steps" => student_steps,
            "meanflow_steps" => meanflow_steps,
            "batch_size" => batch_size, "width" => width, "n_train" => n_train,
            "ot_epsilon" => ot_epsilon, "n_eval" => n_eval,
            "n_teacher" => n_teacher, "projections" => length(angles), "julia" => string(VERSION)))
end

function export_results(file=joinpath(@__DIR__, "results.json"); kwargs...)
    results = run_experiment(; kwargs...)
    open(file, "w") do io
        JSON.print(io, results)
    end
    return results
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    MoonFlows.export_results()
end

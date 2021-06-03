try
    using BarriersTests
    true
catch
    false
end || begin
    let path = joinpath(@__DIR__, "BarriersTests")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    let path = joinpath(@__DIR__, "..", "benchmark", "BarriersBenchmarks")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    using BarriersTests
end

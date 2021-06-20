try
    using SyncBarriersTests
    true
catch
    false
end || begin
    let path = joinpath(@__DIR__, "SyncBarriersTests")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    let path = joinpath(@__DIR__, "..", "benchmark", "SyncBarriersBenchmarks")
        path in LOAD_PATH || push!(LOAD_PATH, path)
    end
    using SyncBarriersTests
end

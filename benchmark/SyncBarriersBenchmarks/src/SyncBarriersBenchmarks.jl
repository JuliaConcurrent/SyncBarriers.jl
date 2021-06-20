module SyncBarriersBenchmarks

using BenchmarkTools: Benchmark, BenchmarkGroup

include("bench_uniform_loops.jl")
include("bench_fuzzy.jl")
include("bench_cml.jl")
include("bench_gcm.jl")

function setup(; uniform_loops = (), fuzzy = (), cml = (), gcm = ())
    suite = BenchmarkGroup()
    suite["uniform_loops"] = BenchUniformLoops.setup(; uniform_loops...)
    suite["fuzzy"] = BenchFuzzy.setup(; fuzzy...)
    suite["cml"] = BenchCML.setup(; cml...)
    suite["gcm"] = BenchGCM.setup(; gcm...)
    return suite
end

function set_smoke_params!(bench)
    bench.params.seconds = 0.001
    bench.params.evals = 1
    bench.params.samples = 1
    bench.params.gctrial = false
    bench.params.gcsample = false
    return bench
end

foreach_benchmark(f!, bench::Benchmark) = f!(bench)
function foreach_benchmark(f!, group::BenchmarkGroup)
    for x in values(group)
        foreach_benchmark(f!, x)
    end
end

function setup_smoke(; ntasks = Threads.nthreads())
    suite = setup(
        fuzzy = (ntasks = ntasks, n = ntasks, m = ntasks, niters = 10),
        cml = (ntasks = ntasks, nsites = ntasks + 2, nsteps = 10),
        gcm = (ntasks = ntasks, nsites = ntasks + 2, nsteps = 10),
    )
    foreach_benchmark(set_smoke_params!, suite)
    return suite
end

function clear()
    BenchUniformLoops.clear()
    BenchFuzzy.clear()
    BenchCML.clear()
    BenchGCM.clear()
end

end  # module SyncBarriersBenchmarks

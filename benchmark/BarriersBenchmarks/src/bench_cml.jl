module BenchCML

using Barriers
using BenchmarkTools

function unsafe_update!(xs, t, indices, f, ϵ)
    for i in indices
        @inbounds xs[i, t+1] =
            (1 - ϵ) * f(xs[i, t]) + ϵ / 2 * (f(xs[i-1, t]) + f(xs[i+1, t]))
    end
end

function sim_seq!(xs, f::F, ϵ) where {F}
    for t in firstindex(xs, 2):lastindex(xs, 2)-1
        unsafe_update!(xs, t, firstindex(xs, 1)+1:lastindex(xs, 1)-1, f, ϵ)
    end
end

function sim_parallel!(xs, f, ϵ, barrier, foreach_parallel, spin)
    ntasks = length(barrier)
    space = firstindex(xs, 1)+1:lastindex(xs, 1)-1
    xchunks = collect(Iterators.partition(space, cld(length(space), ntasks)))
    foreach_parallel(1:ntasks) do itask
        local indices = xchunks[itask]
        for t in firstindex(xs, 2):lastindex(xs, 2)-1
            unsafe_update!(xs, t, indices, f, ϵ)
            cycle!(barrier[itask], spin)
        end
    end
end

prepare_barriers(f, ntasks) = [f(2) for _ in 1:ntasks-1]

function sim_parallel_edges!(xs, f, ϵ, barriers, foreach_parallel, spin)
    ntasks = length(barriers)+1
    space = firstindex(xs, 1)+1:lastindex(xs, 1)-1
    xchunks = collect(Iterators.partition(space, cld(length(space), ntasks)))
    foreach_parallel(1:ntasks) do itask
        local indices = xchunks[itask]
        for t in firstindex(xs, 2):lastindex(xs, 2)-1
            unsafe_update!(xs, t, indices, f, ϵ)
            itask == 1 || cycle!(barriers[itask-1][2], spin)
            itask == ntasks || cycle!(barriers[itask][1], spin)
        end
    end
end

function sim_parallel_nobarrier!(xs, f, ϵ, ntasks, foreach_parallel)
    space = firstindex(xs, 1)+1:lastindex(xs, 1)-1
    xchunks = collect(Iterators.partition(space, cld(length(space), ntasks)))
    for t in firstindex(xs, 2):lastindex(xs, 2)-1
        foreach_parallel(1:ntasks) do itask
            local indices = xchunks[itask]
            unsafe_update!(xs, t, indices, f, ϵ)
        end
    end
end

function parallel_foreach_static(f, xs)
    Threads.@threads :static for x in xs
        f(x)
    end
end

function parallel_foreach_dynamic(f, xs)
    tasks = empty!(Vector{Task}(undef, length(xs)))
    for x in xs
        t = Threads.@spawn f(x)
        push!(tasks, t)
    end
    foreach(wait, tasks)
end

const CACHE = Ref{Any}(nothing)

function setup(;
    spin = nothing,
    # spin = 1000,
    nbranches = 2,
    ntasks = Threads.nthreads(),
    nsteps = 2^10,
    nsites = 2^13 * ntasks,
    a = 1.85,
    ϵ = 0.1,
)
    @debug "BenchCML.setup: spin=$spin nbranches=$nbranches ntasks=$ntasks nsteps=$nsteps nsites=$nsites a=$a ϵ=$ϵ"

    f(x) = 1 - a * x^2

    CACHE[] = zeros(nsites, nsteps)
    CACHE[][:, 1] .= rand(nsites)

    suite = BenchmarkGroup()

    suite["seq"] = @benchmarkable sim_seq!(CACHE[], $f, $ϵ)

    for (label, barrier) in [
        ("dissemination", DisseminationBarrier),
        ("tree", TreeBarrier{nbranches}),
        ("flat-tree", FlatTreeBarrier{nbranches}),
        ("centralized", CentralizedBarrier),
        # ...
    ]
        s1 = suite[label] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel!(
            CACHE[],
            $f,
            $ϵ,
            $barrier($ntasks),
            parallel_foreach_static,
            $spin,
        )
        s1["dynamic"] = @benchmarkable sim_parallel!(
            CACHE[],
            $f,
            $ϵ,
            $barrier($ntasks),
            parallel_foreach_static,
            $spin,
        )
    end

    for (label, barrier) in [
        # ("dissemination-edges", DisseminationBarrier),
        # ("tree-edges", TreeBarrier{nbranches}),
        # ("flat-tree"-edges, FlatTreeBarrier{nbranches}),
        ("centralized-edges", CentralizedBarrier),
        # ...
    ]
        s1 = suite[label] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel_edges!(
            CACHE[],
            $f,
            $ϵ,
            prepare_barriers($barrier, $ntasks),
            parallel_foreach_static,
            $spin,
        )
        s1["dynamic"] = @benchmarkable sim_parallel_edges!(
            CACHE[],
            $f,
            $ϵ,
            prepare_barriers($barrier, $ntasks),
            parallel_foreach_static,
            $spin,
        )
    end

    let s1 = suite["nobarrier"] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel_nobarrier!(
            CACHE[],
            $f,
            $ϵ,
            $ntasks,
            parallel_foreach_static,
        )
        s1["dynamic"] = @benchmarkable sim_parallel_nobarrier!(
            CACHE[],
            $f,
            $ϵ,
            $ntasks,
            parallel_foreach_static,
        )
    end

    return suite
end

function clear()
    CACHE[] = nothing
end

end  # module

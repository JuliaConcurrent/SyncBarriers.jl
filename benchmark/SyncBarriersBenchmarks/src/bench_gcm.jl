module BenchGCM

using SyncBarriers
using BenchmarkTools

function sim_seq!(xs, f::F, ϵ) where {F}
    y = similar(xs, size(xs, 1))
    for t in firstindex(xs, 2):lastindex(xs, 2)-1
        @views begin
            @. y = f(xs[:, t])
            m = sum(y) / size(xs, 1)
            @. xs[:, t+1] = (1 - ϵ) * y + ϵ * m
        end
    end
end

function sim_parallel!(xs, f, ϵ, barrier, foreach_parallel, spin)
    ntasks = length(barrier)
    space = firstindex(xs, 1)+1:lastindex(xs, 1)-1
    xchunks = collect(Iterators.partition(space, cld(length(space), ntasks)))
    foreach_parallel(1:ntasks) do itask
        local indices = xchunks[itask]
        y = similar(xs, length(xchunks[itask]))
        xl = @view xs[xchunks[itask], :]
        for t in firstindex(xs, 2):lastindex(xs, 2)-1
            @views begin
                @. y = f(xl[:, t])
                s = reduce!(barrier[itask], sum(y), spin)
                m = s / size(xs, 1)
                @. xl[:, t+1] = (1 - ϵ) * y + ϵ * m
            end
        end
    end
end

function sim_parallel_nobarrier!(xs, f, ϵ, ntasks, foreach_parallel)
    space = firstindex(xs, 1)+1:lastindex(xs, 1)-1
    y = similar(xs, size(xs, 1))
    sums = similar(xs, ntasks)
    xchunks = collect(Iterators.partition(space, cld(length(space), ntasks)))
    foreach_parallel(1:ntasks) do itask
        local indices = xchunks[itask]
        xl = @view xs[xchunks[itask], :]
        yl = @view y[xchunks[itask]]
        @. yl = f(xl[:, begin])
        sums[itask] = sum(y)
    end
    for t in firstindex(xs, 2):lastindex(xs, 2)-1
        m = sum(sums) / size(xs, 1)
        foreach_parallel(1:ntasks) do itask
            local indices = xchunks[itask]
            xl = @view xs[xchunks[itask], :]
            yl = @view y[xchunks[itask]]
            @views begin
                @. xl[:, t+1] = (1 - ϵ) * yl + ϵ * m
                @. yl = f(xl[:, t+1])
                sums[itask] = sum(yl)
            end
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
    ntasks = Threads.nthreads(),
    nbranches = max(2, cld(ntasks, 4)),
    nsteps = 2^10,
    nsites = 2^13 * ntasks,
    a = 1.85,
    ϵ = 0.1,
)
    @debug "BenchGCM.setup: spin=$spin nbranches=$nbranches ntasks=$ntasks nsteps=$nsteps nsites=$nsites a=$a ϵ=$ϵ"

    f(x) = 1 - a * x^2

    CACHE[] = zeros(nsites, nsteps)
    CACHE[][:, 1] .= rand(nsites)

    suite = BenchmarkGroup()

    suite["seq"] = @benchmarkable sim_seq!(CACHE[], $f, $ϵ)

    for (label, barrier) in [
        ("static-tree", StaticTreeBarrier{nbranches,nbranches,Float64}),
        ("tree", TreeBarrier{nbranches,Float64}),
        ("flat-tree", FlatTreeBarrier{nbranches,Float64}),
        # ...
    ]
        s1 = suite[label] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel!(
            CACHE[],
            $f,
            $ϵ,
            $barrier(+, $ntasks),
            parallel_foreach_static,
            $spin,
        )
        s1["dynamic"] = @benchmarkable sim_parallel!(
            CACHE[],
            $f,
            $ϵ,
            $barrier(+, $ntasks),
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

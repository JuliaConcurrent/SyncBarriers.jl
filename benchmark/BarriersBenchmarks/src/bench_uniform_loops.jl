module BenchUniformLoops

using BenchmarkTools
using Barriers

function work()
    t1 = time_ns() + 100
    while t1 > time_ns()
    end
end

#=
const SINKS = Float64[]
const SINKS_STRIDE = 32
function __init__()
    resize!(SINKS, SINKS_STRIDE * (Threads.nthreads() + 1))
    fill!(SINKS, -1)
end

function work(n = 10)
    i = SINKS_STRIDE * Threads.threadid()
    x = SINKS[i]
    for _ in 1:n
        x = sin(3 * x)
    end
    SINKS[i] = x
end
=#

function spawn_and_wait(ncycles, ntasks)
    tasks = Vector{Task}(undef, ntasks)
    for _ in 1:ncycles
        empty!(tasks)
        for _ in 1:ntasks
            t = Threads.@spawn work()
            push!(tasks, t)
        end
        foreach(wait, tasks)
    end
end

# bad idea?
function spawn_and_barrier(ncycles, ntasks)
    tasks = Vector{Task}(undef, ntasks)
    barrier = Barriers.CentralizedBarrier(ntasks + 1)
    for k in 1:ncycles
        s = mod(k, 2^7) == 0
        s && empty!(tasks)
        for i in 1:ntasks
            t = Threads.@spawn begin
                work()
                Barriers.cycle!(barrier[i])
            end
            s && push!(tasks, t)
        end
        Barriers.cycle!(barrier[ntasks+1])
        s && foreach(wait, tasks)
    end
end

# => works well with dissemination
function barrier_with_static(factory, ncycles, ntasks, spin)
    barrier = factory(ntasks)
    Threads.@threads :static for i in 1:ntasks
        for k in 1:ncycles
            work()
            Barriers.cycle!(barrier[i], spin)
        end
    end
end

# => works well with centralized
function barrier_with_spawn(factory, ncycles, ntasks, spin)
    barrier = factory(ntasks)
    tasks = empty!(Vector{Task}(undef, ntasks))
    for i in 1:ntasks
        t = Threads.@spawn begin
            for k in 1:ncycles
                work()
                Barriers.cycle!(barrier[i], spin)
            end
        end
        push!(tasks, t)
    end
    foreach(wait, tasks)
end

function setup(;
    ncycles::Integer = 2^10,
    ntasks::Integer = Threads.nthreads(),
    spin::Integer = 10_000,
    nbranches_list::AbstractVector{<:Integer} = Int[],
)
    @debug "BenchUniformLoops: ncycles=$ncycles ntasks=$ntasks spin=$spin"

    barrier_list = []
    push_barrier!(name, value) = push!(barrier_list, (name = name, value = value))
    push_barrier!("dissemination", Barriers.DisseminationBarrier),
    push_barrier!("centralized", Barriers.CentralizedBarrier),
    if isempty(nbranches_list)
        if ntasks > 8
            push_barrier!("tree-8", Barriers.TreeBarrier{8})
            push_barrier!("flat-tree-8", Barriers.FlatTreeBarrier{8})
            push_barrier!("static-tree-8-8", Barriers.StaticTreeBarrier{8,8})
        elseif ntasks > 4
            push_barrier!("tree-4", Barriers.TreeBarrier{4})
            push_barrier!("flat-tree-4", Barriers.FlatTreeBarrier{4})
            push_barrier!("static-tree-4-4", Barriers.StaticTreeBarrier{4,4})
        elseif ntasks > 2
            push_barrier!("tree-2", Barriers.TreeBarrier{2})
            push_barrier!("flat-tree-2", Barriers.FlatTreeBarrier{2})
            push_barrier!("static-tree-2-2", Barriers.StaticTreeBarrier{2,2})
        end
    else
        for n in nbranches_list
            push_barrier!("tree-$n", Barriers.TreeBarrier{n})
            push_barrier!("flat-tree-$n", Barriers.FlatTreeBarrier{n})
            push_barrier!("static-tree-$n-$n", Barriers.StaticTreeBarrier{n,n})
        end
    end

    spin_list = [
        (name = "nospin", value = nothing),
        (name = "spin", value = spin),
        # ...
    ]
    loop_list = [
        (name = "static", value = barrier_with_static),
        (name = "spawn", value = barrier_with_spawn),
        # ...
    ]

    suite = BenchmarkGroup()
    suite["wait"] = @benchmarkable spawn_and_wait($ncycles, $ntasks)
    # suite["spawn_and_barrier"] = @benchmarkable spawn_and_barrier($ncycles, $ntasks)
    for barrier in barrier_list
        s1 = suite[string(barrier.name)] = BenchmarkGroup()
        for spinarg in spin_list
            s2 = s1[string(spinarg.name)] = BenchmarkGroup()
            for loop in loop_list
                s2[string(loop.name)] = @benchmarkable(
                    loop($(barrier.value), $ncycles, $ntasks, $(spinarg.value)),
                    setup = begin
                        # Workaround the error " function argument and static parameter
                        # names must be distinct":
                        loop = $(loop.value)
                    end
                )
            end
        end
    end
    return suite
end

function clear() end

end  # module

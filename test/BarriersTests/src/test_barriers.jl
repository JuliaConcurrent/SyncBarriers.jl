module TestBarriers

using Test
using Barriers
using Barriers: Internal

function test_barrier()
    barrier_factories = [
        Barriers.CentralizedBarrier,
        Barriers.DisseminationBarrier,
        Barriers.TreeBarrier{2},
        Barriers.TreeBarrier{3},
        Barriers.FlatTreeBarrier{2},
        Barriers.FlatTreeBarrier{3},
        Barriers.StaticTreeBarrier{4,2},
        Barriers.StaticTreeBarrier{5,3},
        # ...
    ]
    ntasks_list = unique([1, 2, Threads.nthreads(), 2 * Threads.nthreads()])
    @testset for f in barrier_factories, ntasks in ntasks_list
        test_barrier(f, ntasks)
    end
end

function test_barrier(factory, ntasks)
    @debug "`test_barrier($factory, $ntasks)`"
    states = use_barrier(factory, ntasks)
    ncycles = size(states, 1)
    desired = repeat((1:ncycles) .* ntasks, 1, ntasks)
    @test states[:, 1] == (1:ncycles) .* ntasks
    @test all(states[:, 1] .== states)
    @test states == desired
end

function use_barrier(factory, ntasks; kwargs...)
    barrier = factory(ntasks)
    if factory isa Type
        @test barrier isa factory
    end
    return use_barrier(barrier; kwargs...)
end

function use_barrier(barrier::Barriers.Barrier; ncycles = 1000)
    ntasks = length(barrier)
    states = zeros(Int, ncycles, ntasks)
    return use_barrier!(states, barrier)
end

function use_barrier!(states::Matrix, barrier::Barriers.Barrier, spin = nothing)
    ncycles, ntasks = size(states)
    @assert ntasks == length(barrier)
    value = Threads.Atomic{Int}(0)
    @sync for i in 1:ntasks
        Threads.@spawn try
            for k in 1:ncycles
                Threads.atomic_add!(value, 1)
                Barriers.cycle!(barrier[i], spin)
                states[k, i] = value[]
                Barriers.cycle!(barrier[i], spin)
            end
        catch err
            @error(
                "`use_barrier` failed",
                exception = (err, catch_backtrace()),
                i,
                current_task()
            )
            # TODO: close(barrier)
            rethrow()
        end
    end
    return states
end

function test_default_barriers()
    @test Barriers.Barrier(2) isa Barriers.CentralizedBarrier
    @test Barriers.fuzzy_barrier(2) isa Barriers.CentralizedBarrier
    @test Barriers.fuzzy_reduce_barrier(+, Int, 2) isa Barriers.FlatTreeBarrier{2,Int}
    @test Barriers.reduce_barrier(+, Int, 2) isa Barriers.FlatTreeBarrier{2,Int}

    @test Barriers.Barrier(32) isa Barriers.Barrier
    @test Barriers.fuzzy_barrier(32) isa Barriers.Barrier
    @test Barriers.fuzzy_reduce_barrier(+, Int, 32) isa Barriers.Barrier
    @test Barriers.reduce_barrier(+, Int, 32) isa Barriers.Barrier
end

function test_default_barriers_internal()
    @testset for n in 1:32, nthreads in 1:32
        @test Internal._Barrier(n, nthreads) isa Barriers.Barrier
        @test Internal._fuzzy_barrier(n, nthreads) isa Barriers.Barrier
        @test Internal._fuzzy_reduce_barrier(+, Int, n, nthreads) isa Barriers.Barrier
        @test Internal._reduce_barrier(+, Int, n, nthreads) isa Barriers.Barrier
    end
end

end  # module

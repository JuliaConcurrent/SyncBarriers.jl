module TestSyncBarriers

using Test
using SyncBarriers
using SyncBarriers: Internal

function test_barrier()
    barrier_factories = [
        SyncBarriers.CentralizedBarrier,
        SyncBarriers.DisseminationBarrier,
        SyncBarriers.TreeBarrier{2},
        SyncBarriers.TreeBarrier{3},
        SyncBarriers.FlatTreeBarrier{2},
        SyncBarriers.FlatTreeBarrier{3},
        SyncBarriers.StaticTreeBarrier{4,2},
        SyncBarriers.StaticTreeBarrier{5,3},
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

function use_barrier(barrier::SyncBarriers.Barrier; ncycles = 1000)
    ntasks = length(barrier)
    states = zeros(Int, ncycles, ntasks)
    return use_barrier!(states, barrier)
end

function use_barrier!(states::Matrix, barrier::SyncBarriers.Barrier, spin = nothing)
    ncycles, ntasks = size(states)
    @assert ntasks == length(barrier)
    value = Threads.Atomic{Int}(0)
    @sync for i in 1:ntasks
        Threads.@spawn try
            for k in 1:ncycles
                Threads.atomic_add!(value, 1)
                SyncBarriers.cycle!(barrier[i], spin)
                states[k, i] = value[]
                SyncBarriers.cycle!(barrier[i], spin)
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
    @test SyncBarriers.Barrier(2) isa SyncBarriers.CentralizedBarrier
    @test SyncBarriers.fuzzy_barrier(2) isa SyncBarriers.CentralizedBarrier
    @test SyncBarriers.fuzzy_reduce_barrier(+, Int, 2) isa SyncBarriers.FlatTreeBarrier{2,Int}
    @test SyncBarriers.reduce_barrier(+, Int, 2) isa SyncBarriers.FlatTreeBarrier{2,Int}

    @test SyncBarriers.Barrier(32) isa SyncBarriers.Barrier
    @test SyncBarriers.fuzzy_barrier(32) isa SyncBarriers.Barrier
    @test SyncBarriers.fuzzy_reduce_barrier(+, Int, 32) isa SyncBarriers.Barrier
    @test SyncBarriers.reduce_barrier(+, Int, 32) isa SyncBarriers.Barrier
end

function test_default_barriers_internal()
    @testset for n in 1:32, nthreads in 1:32
        @test Internal._Barrier(n, nthreads) isa SyncBarriers.Barrier
        @test Internal._fuzzy_barrier(n, nthreads) isa SyncBarriers.Barrier
        @test Internal._fuzzy_reduce_barrier(+, Int, n, nthreads) isa SyncBarriers.Barrier
        @test Internal._reduce_barrier(+, Int, n, nthreads) isa SyncBarriers.Barrier
    end
end

end  # module

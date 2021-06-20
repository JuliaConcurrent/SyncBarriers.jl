local_sense_states(n) = RecordArrays.fill(true, n; align = 64)

struct CentralizedBarrier <: SyncBarriers.CentralizedBarrier
    n::Int
    count::Threads.Atomic{Int}
    _count_pads::NTuple{ATOMICS_NPADS,Threads.Atomic{Int}}
    sense::Threads.Atomic{Bool}
    _sense_pads::NTuple{ATOMICS_NPADS,Threads.Atomic{Bool}}
    local_sense::typeof(local_sense_states(1))
    waiters::Matrix{OneWayCondition}
end

function CentralizedBarrier(n::Integer)
    count, _count_pads = cache_aligned_atomic(0)
    sense, _sense_pads = cache_aligned_atomic(true)
    return CentralizedBarrier(
        n,
        count,
        _count_pads,
        sense,
        _sense_pads,
        local_sense_states(n),
        [OneWayCondition() for _ in 1:n, _ in 1:2],
    )
end

@inline waiters_for(barrier::CentralizedBarrier, sense::Bool) =
    @view barrier.waiters[:, Int(sense) + 1]

@inline function waiter_for(handle::BarrierHandle{CentralizedBarrier})
    barrier = handle.barrier
    s = barrier.local_sense[handle.i]
    return barrier.waiters[handle.i, Int(s) + 1]
end

function SyncBarriers.arrive!(handle::BarrierHandle{CentralizedBarrier})
    barrier = handle.barrier
    s = !barrier.local_sense[handle.i]
    barrier.local_sense[handle.i] = s
    if Threads.atomic_add!(barrier.count, 1) == barrier.n - 1
        barrier.count[] = 0
        barrier.sense[] = s
        for (j, waiter) in pairs(waiters_for(barrier, s))
            if j != handle.i
                notify(waiter)
            end
        end
        return true
    else
        return false
    end
end

function SyncBarriers.depart!(
    handle::BarrierHandle{CentralizedBarrier},
    spin::Union{Integer,Nothing} = nothing,
)
    barrier = handle.barrier
    s = barrier.local_sense[handle.i]
    waiter = waiter_for(handle)
    sense = barrier.sense
    waitif(() -> sense[] != s, waiter, spin)
    return
end

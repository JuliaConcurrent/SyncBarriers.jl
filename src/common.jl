struct BarrierHandle{Barrier<:SyncBarriers.Barrier}
    barrier::Barrier
    i::Int
end

Base.length(barrier::SyncBarriers.Barrier) = barrier.n

@inline function Base.getindex(barrier::SyncBarriers.Barrier, i::Integer)
    @boundscheck 1 <= i <= length(barrier) || throw(BoundsError(barrier, i))
    return BarrierHandle(barrier, i)
end

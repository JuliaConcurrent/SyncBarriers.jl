struct BarrierHandle{Barrier<:Barriers.Barrier}
    barrier::Barrier
    i::Int
end

Base.length(barrier::Barriers.Barrier) = barrier.n

@inline function Base.getindex(barrier::Barriers.Barrier, i::Integer)
    @boundscheck 1 <= i <= length(barrier) || throw(BoundsError(barrier, i))
    return BarrierHandle(barrier, i)
end

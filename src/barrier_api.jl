# Default barriers:
SyncBarriers.Barrier(n::Integer) = _Barrier(n, Threads.nthreads())
SyncBarriers.fuzzy_barrier(n::Integer) = _fuzzy_barrier(n, Threads.nthreads())
SyncBarriers.fuzzy_reduce_barrier(op, ::Type{T}, n::Integer) where {T} =
    _fuzzy_reduce_barrier(op, T, n, Threads.nthreads())
SyncBarriers.reduce_barrier(op, ::Type{T}, n::Integer) where {T} =
    _reduce_barrier(op, T, n, Threads.nthreads())

# TODO: find the best cutoff
# TODO: make it configurable?
function _Barrier(n::Integer, nthreads::Integer)
    nthreads = min(nthreads, n)
    if nthreads >= 32
        return DisseminationBarrier(n)
    else
        return CentralizedBarrier(n)
    end
end

function _fuzzy_barrier(n::Integer, nthreads::Integer)
    nthreads = min(nthreads, n)
    if nthreads >= 32
        return TreeBarrier{8}(n)
    else
        return CentralizedBarrier(n)
    end
end

function _fuzzy_reduce_barrier(op, ::Type{T}, n::Integer, nthreads::Integer) where {T}
    nthreads = min(nthreads, n)
    if nthreads >= 32
        return TreeBarrier{8,T}(op, n)
    elseif nthreads >= 16
        return FlatTreeBarrier{4,T}(op, n)
    else
        return FlatTreeBarrier{2,T}(op, n)
    end
end

function _reduce_barrier(op, ::Type{T}, n::Integer, nthreads::Integer) where {T}
    nthreads = min(nthreads, n)
    if nthreads >= 32
        return StaticTreeBarrier{8,8,T}(op, n)
    else
        return _fuzzy_reduce_barrier(op, T, n, nthreads)
    end
end

SyncBarriers.CentralizedBarrier(n) = CentralizedBarrier(n)
SyncBarriers.DisseminationBarrier(n) = DisseminationBarrier(n)
SyncBarriers.StaticTreeBarrier{NArrive,NDepart}(n) where {NArrive,NDepart} =
    StaticTreeBarrier{NArrive,NDepart}(n)
SyncBarriers.StaticTreeBarrier{NArrive,NDepart,T}(op, n) where {NArrive,NDepart,T} =
    StaticTreeBarrier{NArrive,NDepart,T}(op, n)
SyncBarriers.TreeBarrier{N}(n) where {N} = TreeBarrier{N}(n)
SyncBarriers.TreeBarrier{N,T}(op, n) where {N,T} = TreeBarrier{N,T}(op, n)
SyncBarriers.FlatTreeBarrier{N}(n) where {N} = FlatTreeBarrier{N}(n)
SyncBarriers.FlatTreeBarrier{N,T}(op, n) where {N,T} = FlatTreeBarrier{N,T}(op, n)

const FuzzyReduceBarrier{T,NBranches} =
    Union{TreeBarrier{NBranches,T},FlatTreeBarrier{NBranches,T}}
const FuzzyBarrier = Union{CentralizedBarrier,TreeBarrier,FlatTreeBarrier}

# Used only in testing ATM:
const ReduceBarrier{T} =
    Union{TreeBarrier{<:Any,T},FlatTreeBarrier{<:Any,T},StaticTreeBarrier{<:Any,<:Any,T}}
acctype(::Type{B}) where {T,B<:ReduceBarrier{T}} = T
acctype(b::SyncBarriers.Barrier) = acctype(typeof(b))

function SyncBarriers.cycle!(
    handle::BarrierHandle{<:FuzzyBarrier},
    spin::Union{Integer,Nothing} = nothing,
)
    islast = SyncBarriers.arrive!(handle)
    islast || SyncBarriers.depart!(handle, spin)
    return islast
end

SyncBarriers.arrive!(handle::BarrierHandle{<:FuzzyReduceBarrier{Nothing}}) =
    SyncBarriers.reduce_arrive!(handle, nothing) === Some(nothing)

Base.summary(io::IO, ::CentralizedBarrier) = show(io, SyncBarriers.CentralizedBarrier)
Base.summary(io::IO, ::DisseminationBarrier) = show(io, SyncBarriers.DisseminationBarrier)
Base.summary(io::IO, ::StaticTreeBarrier{NArrive,NDepart,T}) where {NArrive,NDepart,T} =
    show(io, SyncBarriers.StaticTreeBarrier{NArrive,NDepart,T})
Base.summary(io::IO, ::TreeBarrier{T,N}) where {T,N} = show(io, SyncBarriers.TreeBarrier{T,N})
Base.summary(io::IO, ::FlatTreeBarrier{T,N}) where {T,N} =
    show(io, SyncBarriers.FlatTreeBarrier{T,N})

function Base.show(io::IO, ::MIME"text/plain", barrier::SyncBarriers.Barrier)
    summary(io, barrier)
    print(io, " for ", length(barrier), " task(s)")
end

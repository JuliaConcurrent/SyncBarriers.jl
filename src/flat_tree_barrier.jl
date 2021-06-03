struct FlatNode{NBranches,T,Values<:Union{Nothing,MutableNTuple{NBranches,T}}}
    count::NTuple{2,Threads.Atomic{Int}}
    values::NTuple{2,Values}
end

function FlatNode{NBranches,T}() where {NBranches,T}
    if Base.issingletontype(T)
        Values = Nothing
        values = (nothing, nothing)
    else
        Values = MutableNTuple{NBranches,T}
        values = (Values(), Values())
    end
    count = (Threads.Atomic{Int}(0), Threads.Atomic{Int}(0))
    return FlatNode{NBranches,T,Values}(count, values)
end

struct FlatTreeBarrier{NBranches,T,Op,Values} <: Barriers.FlatTreeBarrier{NBranches,T}
    n::Int
    flags::Matrix{OneWayObservable{Bool}}
    locals::typeof(sense_parity_states(1))
    nodes::Vector{FlatNode{NBranches,T,Values}}
    values::MutableNTuple{2,T}
    op::Op
end
# TODO: check if parity is required

FlatTreeBarrier{NBranches}(n) where {NBranches} =
    FlatTreeBarrier{NBranches,Nothing}(right, n)

function FlatTreeBarrier{NBranches,T}(op::Op, n::Integer) where {NBranches,T,Op}
    @argcheck NBranches isa Integer && NBranches > 1 && T isa Type && n > 0
    nnodes = foldl_leaf_to_root((_, x) -> x.stop, nothing, n, Val(NBranches), 1)
    nodes = [FlatNode{NBranches,T}() for _ in 1:nnodes]
    flags = [OneWayObservable{Bool}(false) for _ in 1:n, _ in 1:2]
    values = MutableNTuple{2,T}()
    return FlatTreeBarrier(
        n,
        flags,
        sense_parity_states(n),
        nodes,
        values,
        op,
    )::FlatTreeBarrier{NBranches,T,Op}
end

function Barriers.reduce!(
    handle::BarrierHandle{<:FlatTreeBarrier},
    value,
    spin::Union{Integer,Nothing} = nothing,
)
    acc1 = Barriers.reduce_arrive!(handle, value)
    acc2 = Barriers.depart!(handle, spin)
    if acc1 isa Some
        @_assert acc2 === something(acc1)
        return something(acc1)
    else
        return acc2
    end
end

function Barriers.reduce_arrive!(
    handle::BarrierHandle{<:FlatTreeBarrier{NBranches,T}},
    value,
) where {NBranches,T}
    value = convert(T, value)
    barrier = handle.barrier
    i = handle.i
    s, parity = inc_sense_parity!(view(barrier.locals, handle.i))
    acc = foldl_leaf_to_root(Some(value), barrier.n, Val(NBranches), i) do acc, x
        node = barrier.nodes[x.inode]
        cnt = node.count[parity+1]
        vals = node.values[parity+1]
        if vals !== nothing
            vals[x.iself] = something(acc)
        end
        if Threads.atomic_add!(cnt, 1) == length(x.branches) - 1
            cnt[] = 0
            if vals === nothing
                return acc  # continue
            else
                a = vals[1]
                for j in x.branches[2:end]
                    a = barrier.op(a, vals[j])
                end
                return Some(a)
            end
        else
            return Break(nothing)
        end
    end
    if acc isa Break
        return nothing
    else
        barrier.values[parity+1] = something(acc)
        for (j, flag) in pairs(@view barrier.flags[:, parity+1])
            flag[] = s
        end
        return acc::Some
    end
end

function Barriers.depart!(
    handle::BarrierHandle{<:FlatTreeBarrier},
    spin::Union{Integer,Nothing} = nothing,
)
    barrier = handle.barrier
    s, parity = prev_sense_parity(view(barrier.locals, handle.i))
    flag = barrier.flags[handle.i, parity+1]
    waitif(!=(s), flag, spin)
    return barrier.values[parity+1]
end

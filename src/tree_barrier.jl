struct Node{NBranches,T,Values<:Union{Nothing,MutableNTuple{NBranches,T}}}
    count::Threads.Atomic{Int}
    sense::Threads.Atomic{Bool}
    winner::NTuple{2,Threads.Atomic{Int}}
    values::NTuple{2,Values}
    waiters::NTuple{2,NTuple{NBranches,OneWayCondition}}
end
# TODO: Clarify why two sets of `values` are required: different rounds can have
# different sets of tasks involved. If not, remove it.

function Node{NBranches,T}() where {NBranches,T}
    if Base.issingletontype(T)
        Values = Nothing
        values = (nothing, nothing)
    else
        Values = MutableNTuple{NBranches,T}
        values = (Values(), Values())
    end
    return Node{NBranches,T,Values}(
        Threads.Atomic{Int}(0),
        Threads.Atomic{Bool}(true),
        (Threads.Atomic{Int}(0), Threads.Atomic{Int}(0)),
        values,
        ntuple(_ -> ntuple(_ -> OneWayCondition(), NBranches), 2),
    )
end

struct TreeBarrier{NBranches,T,Op,Values} <: Barriers.TreeBarrier{NBranches,T}
    n::Int
    local_sense::Vector{Bool}  # TODO: pad
    nodes::Vector{Node{NBranches,T,Values}}
    values::MutableNTuple{2,T}
    op::Op
end

TreeBarrier{NBranches}(n) where {NBranches} = TreeBarrier{NBranches,Nothing}(right, n)

function TreeBarrier{NBranches,T}(op::Op, n::Integer) where {NBranches,T,Op}
    @argcheck NBranches isa Integer && NBranches > 1 && T isa Type && n > 0
    local_sense = [true for _ in 1:n]
    nnodes = foldl_leaf_to_root((_, x) -> x.stop, nothing, n, Val(NBranches), 1)
    nodes = [Node{NBranches,T}() for _ in 1:nnodes]
    values = MutableNTuple{2,T}()
    return TreeBarrier(n, local_sense, nodes, values, op)::TreeBarrier{NBranches,T,Op}
end

function foldl_leaf_to_root(
    rf,
    acc,
    n::Integer,
    ::Val{NBranches},
    i::Integer,
) where {NBranches}
    offset = 0
    width = n  # number of nodes for each depth
    while true
        width, nlast = divrem(width, NBranches)
        width += nlast > 0
        q, r = divrem(i - 1, NBranches)
        i = q + 1
        if nlast > 0 && i == width
            branches = 1:nlast
        else
            branches = 1:NBranches
        end
        acc = rf(
            acc,
            (
                inode = offset + i,       # node = nodes[inode]
                iself = r + 1,            # node.values[_][iself] is my slot
                branches = branches,      # node.values[_][brancehs] is me + siblings
                offset = offset,
                stop = offset + width,
                width = width,
            ),
        )
        acc isa Break && break
        width == 1 && break
        offset += width
    end
    return acc
end

function recurse_leaf_to_root(
    rf,
    acc,
    n::Integer,
    ::Val{NBranches},
    i::Integer,
) where {NBranches}
    function rec(acc, offset, width)
        width, nlast = divrem(width, NBranches)
        width += nlast > 0
        q, r = divrem(i - 1, NBranches)
        i = q + 1
        if nlast > 0 && i == width
            branches = 1:nlast
        else
            branches = 1:NBranches
        end
        isroot = width == 1
        x = (
            inode = offset + i,       # node = nodes[inode]
            iself = r + 1,            # node.values[_][iself] is my slot
            branches = branches,      # node.values[_][brancehs] is me + siblings
            offset = offset,
            stop = offset + width,
            isroot = isroot,
        )
        rf(acc, x) do acc
            acc isa Break && return acc
            isroot && return acc
            rec(acc, offset + width, width)
        end
    end
    return rec(acc, 0, n)
end

function _reduce_arrive!(
    handle::BarrierHandle{<:TreeBarrier{NBranches,T}},
    value,
    ::Val{ShouldWait},
    spin = nothing,
) where {_F,NBranches,T,ShouldWait}
    value = convert(T, value)
    barrier = handle.barrier
    i = handle.i
    s = barrier.local_sense[handle.i] = !barrier.local_sense[handle.i]
    return recurse_leaf_to_root(
        Some(value),
        barrier.n,
        Val(NBranches),
        i,
    ) do recurse, acc, x
        node = barrier.nodes[x.inode]
        vals = node.values[s+1]
        if vals !== nothing
            vals[x.iself] = something(acc)
        end
        if Threads.atomic_add!(node.count, 1) == length(x.branches) - 1
            if !ShouldWait
                node.winner[s+1][] = x.iself
            end
            if vals !== nothing
                a = vals[1]
                for j in x.branches[2:end]
                    a = barrier.op(a, vals[j])
                end
                if x.isroot
                    barrier.values[s+1] = a
                end
                acc = Some(a)
            end
            acc0 = acc
            acc = recurse(acc)
            if acc isa Break
                return acc
            end
            if !ShouldWait
                if x.isroot
                    for node in barrier.nodes
                        node.winner[!s+1][] = 0
                    end
                end
            end
            node.count[] = 0
            node.sense[] = s
            for (j, waiter) in pairs(node.waiters[s+1])
                if j != x.iself
                    notify(waiter)
                end
            end
            return acc
        else
            if ShouldWait
                sense = node.sense
                waitif(() -> sense[] != s, node.waiters[s+1][x.iself], spin)
                return nothing
            else
                return Break(nothing)
            end
        end
    end
end

function Barriers.reduce!(
    handle::BarrierHandle{<:TreeBarrier{NBranches,T}},
    value,
    spin::Union{Nothing,Integer} = nothing,
) where {NBranches,T}
    acc = _reduce_arrive!(handle, value, Val(true), spin)::Union{Nothing,Some}
    barrier = handle.barrier
    s = barrier.local_sense[handle.i]
    if acc isa Some
        @_assert barrier.values[s+1] === something(acc)
        return something(acc)
    else
        return barrier.values[s+1]
    end
end

function Barriers.reduce_arrive!(
    handle::BarrierHandle{<:TreeBarrier{NBranches,T}},
    value,
) where {NBranches,T}
    acc = _reduce_arrive!(handle, value, Val(false))
    if acc isa Break
        return nothing
    else
        return acc::Some
    end
end

function Barriers.depart!(
    handle::BarrierHandle{<:TreeBarrier{NBranches}},
    spin::Union{Integer,Nothing} = nothing,
) where {NBranches}
    barrier = handle.barrier
    s = barrier.local_sense[handle.i]
    recurse_leaf_to_root(nothing, barrier.n, Val(NBranches), handle.i) do recurse, _, x
        node = barrier.nodes[x.inode]
        if node.winner[s+1][] == x.iself
            if x.isroot  # already notified during arrive
                return Break(nothing)
            end
            acc = recurse(nothing)
            acc isa Break && return acc

            node.count[] = 0
            node.sense[] = s
            for (j, waiter) in pairs(node.waiters[s+1])
                if j != x.iself
                    notify(waiter)
                end
            end
        else
            sense = node.sense
            waitif(() -> sense[] != s, node.waiters[s+1][x.iself], spin)
        end
        return nothing
    end
    return barrier.values[s+1]
end

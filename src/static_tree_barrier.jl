struct StaticFlagNode{NBranches,T,Value<:Cell{T}}
    nchildren::Int
    children::NTuple{NBranches,Int}
    flag::OneWayObservable{Bool}
    value::Value
end

StaticFlagNode{NBranches,T,Value}(
    nchildren,
    children,
    flag,
) where {NBranches,T,Value<:Cell{T}} =
    StaticFlagNode{NBranches,T,Value}(nchildren, children, flag, Value())

function concrete(::Type{StaticFlagNode{NBranches,T}}) where {NBranches,T}
    if Base.issingletontype(T)
        return StaticFlagNode{NBranches,T,SingletonCell{T}}
    else
        return StaticFlagNode{NBranches,T,MutableCell{T}}
    end
end

struct StaticTreeBarrier{NArrive,NDepart,T,Value,Op} <:
       Barriers.StaticTreeBarrier{NArrive,NDepart,T}
    n::Int
    local_sense::Vector{Bool}  # TODO: pad
    arrives::Vector{StaticFlagNode{NArrive,T,Value}}
    departs::Vector{StaticFlagNode{NDepart,Nothing,SingletonCell{Nothing}}}
    op::Op
end

StaticTreeBarrier{NArrive,NDepart}(n::Integer) where {NArrive,NDepart} =
    StaticTreeBarrier{NArrive,NDepart,Nothing}(right, n)

function StaticTreeBarrier{NArrive,NDepart,T}(op, n::Integer) where {NArrive,NDepart,T}
    @argcheck n > 0
    arrives = Vector{concrete(StaticFlagNode{NArrive,T})}(undef, n)
    departs = Vector{concrete(StaticFlagNode{NDepart,Nothing})}(undef, n)
    static_tree!(arrives)
    static_tree!(departs)
    local_sense = [false for _ in 1:n]
    return StaticTreeBarrier(n, local_sense, arrives, departs, op)
end

function static_tree_depth(B, n)
    len(d) = (B^d - 1) ÷ (B - 1)
    d = ceil(Int, log(B, (B - 1) * n + 1))
    @assert len(d - 1) <= n <= len(d)
    return d
end

function static_tree!(nodes::AbstractVector{<:StaticFlagNode{NBranches}}) where {NBranches}
    i = _static_tree!(nodes, 1, 1, static_tree_depth(NBranches, length(nodes)))
    @assert i == length(nodes) + 1
end

# Filling nodes in depth-first order so that the reduction does not require commutativity.
function _static_tree!(
    nodes::AbstractVector{<:Node},
    i,
    depth,
    maxdepth,
) where {NBranches,Node<:StaticFlagNode{NBranches}}
    children = ntuple(_ -> firstindex(nodes) - 1, Val(NBranches))
    nchildren = 0
    if depth < maxdepth
        for k in 1:NBranches
            i <= length(nodes) - depth || break
            i = _static_tree!(nodes, i, depth + 1, maxdepth)
            nchildren += 1
            children = Base.setindex(children, i - 1, k)
        end
    end
    nodes[i] = Node(nchildren, children, OneWayObservable{Bool}(false))
    return i + 1
end

function foldr_children(op, acc, nodes::AbstractVector{<:StaticFlagNode}, i)
    node = nodes[i]
    for k in node.nchildren:-1:1
        acc = op(nodes[node.children[k]], acc)
    end
    return acc
end

# The iteration order of foldr_children and foreach_child_flag are different so
# that the communication is done in FIFO manner. (TODO: check if it matters)
function foreach_child_flag(f::F, nodes, i) where {F}
    node = nodes[i]
    for k in 1:node.nchildren
        f(nodes[node.children[k]].flag)
    end
    return
end

Barriers.cycle!(
    handle::BarrierHandle{<:StaticTreeBarrier{<:Any,<:Any,Nothing}},
    spin::Union{Nothing,Integer} = nothing,
) = Barriers.reduce!(handle, nothing, spin)

function Barriers.reduce!(
    handle::BarrierHandle{<:StaticTreeBarrier{<:Any,<:Any,T}},
    value,
    spin::Union{Nothing,Integer} = nothing,
) where {T}
    value = convert(T, value)
    i = handle.i
    barrier = handle.barrier

    acc = foldr_children(value, barrier.arrives, i) do node, value
        waitif(!=(true), node.flag, spin)
        node.flag.value[] = false  # for next episode
        barrier.op(node.value[], value)
    end
    barrier.arrives[i].value[] = acc
    barrier.arrives[i].flag[] = true

    sense = barrier.local_sense[i] = !barrier.local_sense[i]
    root_node = length(barrier)
    if i != root_node
        waitif(!=(sense), barrier.departs[i].flag, spin)
    end
    foreach_child_flag(barrier.departs, i) do flag
        flag[] = sense
    end

    return barrier.arrives[root_node].value[]
end

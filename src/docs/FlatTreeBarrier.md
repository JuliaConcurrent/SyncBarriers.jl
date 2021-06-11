    FlatTreeBarrier{NBranches}(ntasks::Integer)
    FlatTreeBarrier{NBranches,T}(op, ntasks::Integer)

Create the tree barrier for `ntasks` tasks with the branching factor specified
by the type parameter `NBranches::Integer`.  The departure is done serially
(hence "flat").

It support fuzzy reduce barrier methods if the associative operations `op` and
its domain `T` are given. Otherwise, it only supports fuzzy barrier methods.

Supported methods: [`cycle!`](@ref), [`arrive!`](@ref), [`depart!`](@ref)
[`reduce!`](@ref).  [`reduce_arrive!`](@ref).

    StaticTreeBarrier{NArrive,NDepart}(ntasks::Integer)
    StaticTreeBarrier{NArrive,NDepart,T}(op, ntasks::Integer)

Create the static tree barrier for `ntasks` tasks with the branching factor for
arrival `NArrive::Integer` and departure `NDepart::Integer` specified by the
type parameters.

It support fuzzy reduce barrier methods if the associative operations `op` and
its domain `T` are given. Otherwise, it only supports fuzzy barrier methods.

It provides the best performance for large `ntasks` (⪆ 32) when reduction is
needed.

Supported methods: [`cycle!`](@ref), [`reduce!`](@ref)

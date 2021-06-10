    depart!(barrier[i])
    depart!(barrier[i]) -> acc::T

Wait for all calls to [`arrive!(barrier[i])`](@ref Barriers.arrive!) or
[`reduce_arrive!(barrier[i], _)`](@ref Barriers.reduce_arrive!) for `i = 1, 2,
..., ntasks`.

If the `barrier` is a fuzzy reduce barrier (created, e.g., by
[`fuzzy_reduce_barrier(op, T, ntasks)`](@ref Barriers.fuzzy_reduce_barrier)), it
returns the result of reduction started by the prior call to
[`reduce_arrive!(barrier[i], xᵢ::T)`](@ref Barriers.reduce_arrive!).

Note that not all `Barrier` subtypes support `depart!.`

See [`fuzzy_barrier`](@ref), [`arrive!`](@ref), [`reduce_arrive!`](@ref).

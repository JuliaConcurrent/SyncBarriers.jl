    fuzzy_barrier(ntasks::Integer) -> barrier::Barrier

Create a *fuzzy barrier* for `ntasks` tasks.  In addition to the methods
supported by "plain" barriers (see [`Barrier`](@ref)), fuzzy barriers support
[`arrive!(barrier[i])`](@ref Barriers.arrive!) and [`depart!(barrier[i])`](@ref
Barriers.depart!) to do [`cycle!`](@ref) in two steps.

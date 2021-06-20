    fuzzy_reduce_barrier(op, T::Type, ntasks::Integer) -> barrier::Barrier

Create a *fuzzy reduce barrier* for `ntasks` tasks.  In addition to the methods
supported by reduce barriers (see [`reduce_barrier`](@ref)], fuzzy reduce
barriers support [`reduce_arrive!(barrier[i], xᵢ)`](@ref
SyncBarriers.reduce_arrive!) and [`depart!(barrier[i])`](@ref SyncBarriers.depart!).

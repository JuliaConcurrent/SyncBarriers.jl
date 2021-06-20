    Barrier(ntasks::Integer) -> barrier

Create a barrier for `ntasks` tasks.  Call [`cycle!(barrier[i])`](@ref
SyncBarriers.cycle!) in the `i`-th task for waiting for other tasks to arrive at the
same phase.

The actual returned concrete type is not the part of API. It is
[`CentralizedBarrier`](@ref) for small `ntasks` and
[`DisseminationBarrier`](@ref) for large `ntasks`.

Supported method: [`cycle!`](@ref)

    reduce_barrier(op, T::Type, ntasks::Integer) -> barrier::Barrier

Create a *reduce barrier* for `ntasks` tasks.  A reduce barrier supports
computing a reduction with an associative operator `op(::T, ::T)` across tasks
by calling [`reduce!(barrier[i], xᵢ::T)`](@ref Barriers.reduce!).

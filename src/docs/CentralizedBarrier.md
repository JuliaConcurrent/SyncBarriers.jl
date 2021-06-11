    CentralizedBarrier(ntasks::Integer)

Create the sense-reversing centralized barrier for `ntasks` tasks.  It supports
fuzzy barrier methods.  For small `ntasks` (⪅ 32), it provides the best
performance.

Supported methods: [`cycle!`](@ref), [`arrive!`](@ref), [`depart!`](@ref)

    DisseminationBarrier(ntasks::Integer)

Create the dissemination barrier for `ntasks` tasks.  It provides the best
performance especially for large `ntasks` (⪆ 32).

Supported method: [`cycle!`](@ref)

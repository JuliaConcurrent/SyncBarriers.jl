    reduce!(barrier[i], xᵢ::T) -> acc::T

Using a reduce barrier `barrier` (created, e.g., by [`reduce_barrier(⊗, T,
n)`](@ref SyncBarriers.reduce_barrier)), it computes `acc = x₁ ⊗ x₂ ⊗ ⋯ ⊗ xₙ`.

# Examples

```julia
julia> using SyncBarriers

julia> xs = Float64[1:4;];

julia> barrier = reduce_barrier(+, Float64, length(xs));

julia> @sync for i in eachindex(xs)
           Threads.@spawn begin
               x = i^2
               s = reduce!(barrier[i], x)
               m = s / length(xs)
               xs[i] = x - m
           end
       end

julia> xs
4-element Vector{Float64}:
 -6.5
 -3.5
  1.5
  8.5
```

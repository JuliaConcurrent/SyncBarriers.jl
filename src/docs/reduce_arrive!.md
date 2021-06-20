    reduce_arrive!(barrier[i], xᵢ::T)

Using a fuzzy reduce barrier `barrier` (created, e.g., by
[`fuzzy_reduce_barrier(op, T, ntasks)`](@ref SyncBarriers.fuzzy_reduce_barrier)), it
initiates the reduction across tasks. The result of the reduction can be
retrieved by a call to [`depart!(barrier[i])`](@ref SyncBarriers.depart!) once all
tasks have called `reduce_arrive!`.

# Examples

```julia
julia> using SyncBarriers

julia> xs = Float64[1:4;];

julia> ys = similar(xs);

julia> barrier = fuzzy_reduce_barrier(+, Float64, length(xs));

julia> @sync for i in eachindex(xs)
           Threads.@spawn begin
               x = i^2
               reduce_arrive!(barrier[i], x)
               ys[i] = x - 1
               s = depart!(barrier[i])
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

julia> ys
4-element Vector{Float64}:
  0.0
  3.0
  8.0
 15.0
```

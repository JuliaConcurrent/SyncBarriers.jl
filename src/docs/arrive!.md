    arrive!(barrier[i])

Signal that the `i::Integer`-th task has reached a certain phase but postpone
the synchronization for the departure.

A call to `cycle!` is equivalent to `arrive!` followed by `depart!`.  However,
the task calling `arrive!` can work on some other local computations before
calling `depart!` which waits for other tasks to call `arrive!`.

Note that not all `Barrier` subtypes support `arrive!.`

See [`fuzzy_barrier`](@ref), [`depart!`](@ref).

# Examples

```julia
julia> using SyncBarriers

julia> xs = [1:3;];

julia> ys = similar(xs);

julia> barrier = fuzzy_barrier(3);

julia> @sync for i in 1:3
           Threads.@spawn begin
               x = i^2
               xs[i] = x
               arrive!(barrier[i])  # does not `wait`
               ys[i] = x - 1  # do some work while waiting for other tasks
               depart!(barrier[i])  # ensure all tasks have reached `arrive!`
               xs[mod1(i + 1, 3)] -= x
           end
       end

julia> xs
3-element Vector{Int64}:
 -8
  3
  5

julia> ys
3-element Vector{Int64}:
 0
 3
 8
```

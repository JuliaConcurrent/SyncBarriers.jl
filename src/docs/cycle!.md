    cycle!(barrier[i])

Using a `barrier::Barrier`, signal that the `i::Integer`-th task has reached a
certain phase of the program and wait for other tasks to reach the same phase.

# Examples

```julia
julia> using Barriers

julia> xs = [1:3;];

julia> barrier = Barrier(3);

julia> @sync for i in 1:3
           Threads.@spawn begin
               x = i^2
               xs[i] = x
               cycle!(barrier[i])
               xs[mod1(i + 1, 3)] -= x
           end
       end

julia> xs
3-element Vector{Int64}:
 -8
  3
  5
```

# SyncBarriers

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tkf.github.io/SyncBarriers.jl/dev)

SyncBarriers.jl provides various implementations of
[barrier](https://en.wikipedia.org/wiki/Barrier_(computer_science)) for shared
memory synchronization and reductions in concurrent Julia programs.  It respects
the cooperative multitasking nature of Julia's task system while allowing the
programmers to express and leverage the structure of the parallelism in their
program.

See the [documentation](https://tkf.github.io/SyncBarriers.jl/dev) for more
information.

**Note:** Appropriate insertion of barriers for correct and efficient parallel
program is rather hard.  For casual programming, it is recommended to ues
[higher-level data-parallel
approaches](https://juliafolds.github.io/data-parallelism/).

## A toy example

```julia
julia> using SyncBarriers

julia> xs = zeros(Bool, 20);

julia> xs[end÷2] = true;

julia> barrier = Barrier(length(xs) - 2);

julia> @sync for i in 2:length(xs)-1
           b = barrier[i-1]
           Threads.@spawn begin
               if i == 2
                   println()
                   join(stdout, (" █"[x + 1] for x in xs))
                   println()
               end
               for _ in 1:8
                   cycle!(b)               # wait for print
                   l, c, r = xs[i-1:i+1]   # (loading)
                   cycle!(b)               # wait for load
                   xs[i] = l ⊻ (c | r)     # (storing)
                   cycle!(b)               # wait for store
                   if i == 2
                       join(stdout, (" █"[x + 1] for x in xs))
                       println()
                   end
               end
           end
       end

         █
        ███
       ██  █
      ██ ████
     ██  █   █
    ██ ████ ███
   ██  █    █  █
  ██ ████  ██████
 ██  █   ███     █
```

See the
[benchmarks](https://github.com/tkf/SyncBarriers.jl/tree/master/benchmark/SyncBarriersBenchmarks/src)
for examples with actual performance considerations.

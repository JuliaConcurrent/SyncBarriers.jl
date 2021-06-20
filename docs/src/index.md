# SyncBarriers.jl

```@docs
SyncBarriers
```

## Barrier factories

Barrier factories create a barrier with a given property without specifying the
actual implementation. They use simple heuristics to determine an appropriate
implementation.

```@docs
Barrier
reduce_barrier
fuzzy_barrier
fuzzy_reduce_barrier
```

## Barrier constructors

```@docs
CentralizedBarrier
DisseminationBarrier
StaticTreeBarrier
TreeBarrier
FlatTreeBarrier
```

## Synchronizing operations

```@docs
cycle!
arrive!
depart!
reduce!
reduce_arrive!
```

baremodule Barriers

export
    # Types:
    Barrier,
    CentralizedBarrier,
    DisseminationBarrier,
    FlatTreeBarrier,
    FuzzyBarrier,
    StaticTreeBarrier,
    TreeBarrier,
    # Functions:
    arrive!,
    cycle!,
    depart!,
    fuzzy_barrier,
    fuzzy_reduce_barrier,
    reduce!,
    reduce_arrive!,
    reduce_barrier

abstract type Barrier end

# Factories
function fuzzy_barrier end
function fuzzy_reduce_barrier end
function reduce_barrier end

# Synchronizing API
function cycle! end
function arrive! end
function depart! end
function reduce! end
function reduce_arrive! end

abstract type CentralizedBarrier <: Barrier end
abstract type DisseminationBarrier <: Barrier end
abstract type TreeBarrier{N,T} <: Barrier end
abstract type FlatTreeBarrier{N,T} <: Barrier end
abstract type StaticTreeBarrier{NArrive,NDepart,T} <: Barrier end

module Internal

using ArgCheck: ArgCheck, @argcheck, @check
using RecordArrays

using ..Barriers: Barriers

include("utils.jl")
include("oneway.jl")
include("common.jl")
include("centralized_barrier.jl")
include("dissemination_barrier.jl")
include("static_tree_barrier.jl")
include("tree_barrier.jl")
include("flat_tree_barrier.jl")
include("barrier_api.jl")

end  # module Internal

end  # baremodule Barriers

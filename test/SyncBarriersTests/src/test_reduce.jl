module TestReduce

using Test
using SyncBarriers
using SyncBarriers.Internal: BarrierHandle, acctype

# An example of non-commutative reduction
function larger((i, a), (j, b))
    if a < b
        (j, b)
    else
        (i, a)
    end
end

initof(op, T) = Base.reduce_empty(op, T)
initof(::typeof(xor), T::Type{<:Integer}) = zero(T)
initof(::typeof(larger), ::Type{Tuple{I,X}}) where {I,X} = (zero(I), typemin(X))

samples(::Type{T}) where {T<:Real} = T(100):T(999)
samples(::Type{T}) where {I,X,T<:Tuple{I,X}} = collect(zip(samples(I), samples(X)))

function test_reduce()
    @testset "+" begin
        test_reduce(+, Int)
    end
    @testset "xor" begin
        test_reduce(xor, UInt)
    end
    @testset "larger" begin
        test_reduce(larger, Tuple{Int,Float64})
    end
end

struct TreeBarrier′{NBranches,T,B<:SyncBarriers.TreeBarrier{NBranches,T}} <: SyncBarriers.Barrier
    barrier::B
end

Base.length(barrier::TreeBarrier′) = length(barrier.barrier)

TreeBarrier′{NBranches,T}(op, n) where {NBranches,T} =
    TreeBarrier′(SyncBarriers.TreeBarrier{NBranches,T}(op, n))
SyncBarriers.Internal.acctype(::Type{B}) where {T,B<:TreeBarrier′{<:Any,T}} = T

function SyncBarriers.reduce!(
    handle::BarrierHandle{<:TreeBarrier′},
    value,
    spin::Union{Nothing,Integer} = nothing,
)
    handle = BarrierHandle(handle.barrier.barrier, handle.i)
    SyncBarriers.reduce_arrive!(handle, value)
    SyncBarriers.depart!(handle, spin)
end

function test_reduce(op, T)
    barrier_factories = [
        SyncBarriers.StaticTreeBarrier{2,2,T},
        SyncBarriers.StaticTreeBarrier{3,4,T},
        SyncBarriers.TreeBarrier{3,T},
        SyncBarriers.FlatTreeBarrier{2,T},
        SyncBarriers.FlatTreeBarrier{3,T},
        TreeBarrier′{2,T},
        TreeBarrier′{3,T},
        # ...
    ]
    ntasks_list = unique([1, 2, Threads.nthreads(), 2 * Threads.nthreads()])
    @testset for f in barrier_factories, ntasks in ntasks_list
        @debug "Testing `test_reduce($op, $f, $ntasks)`"
        test_reduce(op, f, ntasks)
    end
end

function test_reduce(op, factory, ntasks)
    output, input = use_barrier(op, factory, ntasks)
    desired =
        repeat(reduce(op, input; init = initof(op, eltype(output)), dims = 2), 1, ntasks)
    @test output[:, 1] == desired[:, 1]
    @test all(output[:, 1] .== output)
    @test output == desired
end

function use_barrier(op, factory, ntasks; kwargs...)
    barrier = factory(op, ntasks)
    if factory isa Type
        @test barrier isa factory
    end
    return use_barrier(barrier; kwargs...)
end

function use_barrier(barrier::SyncBarriers.Barrier; ncycles = 1000)
    ntasks = length(barrier)
    input = rand(samples(acctype(barrier)), ncycles, ntasks)
    output = similar(input)
    return use_barrier!(output, input, barrier)
end

function use_barrier!(
    output::Matrix,
    input::Matrix,
    barrier::SyncBarriers.Barrier,
    spin = nothing,
)
    ncycles, ntasks = size(output)
    @assert ntasks == length(barrier)
    @sync for i in 1:ntasks
        Threads.@spawn try
            for k in 1:ncycles
                output[k, i] = SyncBarriers.reduce!(barrier[i], input[k, i], spin)
            end
        catch err
            @error(
                "`use_barrier` failed",
                exception = (err, catch_backtrace()),
                i,
                current_task()
            )
            # TODO: close(barrier)
            rethrow()
        end
    end
    return output, input
end

end  # module

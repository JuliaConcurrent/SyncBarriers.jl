function debugging end
enable_debug() = @eval debugging() = true
disable_debug() = @eval debugging() = false
enable_debug()
# disable_debug()

macro _assert(args...)
    call = Expr(
        :macrocall,
        getfield(ArgCheck, Symbol("@check")),  # injecting the callable for esc
        __source__,
        args...,
    )
    ex = Expr(:block, __source__, call)
    quote
        if $debugging()
            $ex
        end
        nothing
    end |> esc
end

pause() = ccall(:jl_cpu_pause, Cvoid, ())

function ceillog2(n::Integer)
    n > 0 || throw(DomainError(n))
    i = trailing_zeros(n)
    j = 8 * sizeof(n) - leading_zeros(n) - 1
    if i == j
        return i
    else
        return j + 1
    end
end

abstract type Cell{T} end
mutable struct MutableCell{T} <: Cell{T}
    value::T
    # TODO: pad
    MutableCell{T}() where {T} = new{T}()
end
struct SingletonCell{T} <: Cell{T} end

@inline Base.getindex(cell::MutableCell{T}) where {T} = cell.value
@inline Base.getindex(::SingletonCell{T}) where {T} = T.instance
@inline Base.setindex!(cell::MutableCell{T}, value::T) where {T} = cell.value = value
@inline Base.setindex!(::SingletonCell{T}, value::T) where {T} = value

USE_PADDED_ATOMICS = true
# USE_PADDED_ATOMICS = false
if USE_PADDED_ATOMICS
    # TODO: use RecordArrays to allocate atomics
    # TODO: load cache line size
    const ATOMICS_NPADS = 7

    # The allocator is very likely to hand over objects allocated at consecutive locations
    function cache_aligned_atomic(x::T) where {T}
        a1 = Threads.Atomic{T}(x)
        a2 = Threads.Atomic{T}(x)
        a3 = Threads.Atomic{T}(x)
        a4 = Threads.Atomic{T}(x)
        a5 = Threads.Atomic{T}(x)
        a6 = Threads.Atomic{T}(x)
        a7 = Threads.Atomic{T}(x)
        a8 = Threads.Atomic{T}(x)
        if mod(UInt(pointer_from_objref(a1)), 64) == 0
            return (a1, (a2, a3, a4, a5, a6, a7, a8))
        elseif mod(UInt(pointer_from_objref(a2)), 64) == 0
            return (a2, (a1, a3, a4, a5, a6, a7, a8))
        elseif mod(UInt(pointer_from_objref(a3)), 64) == 0
            return (a3, (a1, a2, a4, a5, a6, a7, a8))
        else
            return (a4, (a1, a2, a3, a5, a6, a7, a8))
        end
    end
else
    const ATOMICS_NPADS = 0
    cache_aligned_atomic(x::T) where {T} = (Threads.Atomic{T}(x), ())
end

""" Something like Transducers.Reduced """
struct Break{T}
    value::T
end

right(_, x) = x

mutable struct ExperimentalMutableNTuple{N,T}
    values::NTuple{N,T}
    ExperimentalMutableNTuple{N,T}(values::NTuple{N,T}) where {N,T} = new{N,T}(values)
    ExperimentalMutableNTuple{N,T}() where {N,T} = new{N,T}()
end

@inline Base.getindex(mut::ExperimentalMutableNTuple, i) = mut.values[i]
# TODO: need to use unsafe_store! to make it data race-free
#=
@inline function Base.setindex!(mut::ExperimentalMutableNTuple{N,T}, v, i) where {T}
    @boundscheck 1 <= i <= N || throw(BoundsError(mut, i))
    if Base.issingletontype(T)
        return
    elseif Base.isimmutable(T)
    else
    end
    mut.values = Base.setindex(mut.values, v, i)
end
=#

struct FallbackMutableNTuple{N,T}
    values::Vector{T}
    FallbackMutableNTuple{N,T}(values::NTuple{N,T}) where {N,T} = new{N,T}(collect(values))
    FallbackMutableNTuple{N,T}() where {N,T} = new{N,T}(Vector{T}(undef, N))
end

Base.@propagate_inbounds Base.getindex(mut::FallbackMutableNTuple, i) = mut.values[i]
Base.@propagate_inbounds Base.setindex!(mut::FallbackMutableNTuple, v, i) =
    mut.values[i] = v

USE_EXPERIMENTAL_MUTABLE_NTUPLE = false
if USE_EXPERIMENTAL_MUTABLE_NTUPLE
    const MutableNTuple = ExperimentalMutableNTuple
else
    const MutableNTuple = FallbackMutableNTuple
end

function define_docstrings()
    docstrings = [:SyncBarriers => joinpath(dirname(@__DIR__), "README.md")]
    docsdir = joinpath(@__DIR__, "docs")
    for filename in readdir(docsdir)
        stem, ext = splitext(filename)
        ext == ".md" || continue
        name = Symbol(stem)
        name in names(SyncBarriers, all=true) || continue
        push!(docstrings, name => joinpath(docsdir, filename))
    end
    for (name, path) in docstrings
        include_dependency(path)
        doc = read(path, String)
        doc = replace(doc, r"^```julia"m => "```jldoctest $name")
        doc = replace(doc, "<kbd>TAB</kbd>" => "_TAB_")
        @eval SyncBarriers $Base.@doc $doc $name
    end
end

const OWC_EMPTY = 0
const OWC_WAITING = 1
const OWC_NOTIFYING = 2
const OWC_CLOSED = 3

"""
    OneWayCondition()

Single-reader single-writer condition variable.
"""
mutable struct OneWayCondition
    state::Threads.Atomic{Int}
    _pads::NTuple{ATOMICS_NPADS,Threads.Atomic{Int}}
    task::Union{Task,Nothing}
end

function OneWayCondition()
    state, _pads = cache_aligned_atomic(OWC_EMPTY)
    return OneWayCondition( state, _pads, nothing)
end

function Base.notify(cond::OneWayCondition)
    @_assert cond.state[] in (OWC_EMPTY, OWC_WAITING)
    state = Threads.atomic_cas!(cond.state, OWC_WAITING, OWC_NOTIFYING)
    @_assert state in (OWC_EMPTY, OWC_WAITING)
    if state === OWC_WAITING
        schedule(cond.task)
    end
    return
end

function waitif(f, cond::OneWayCondition, spin::Union{Nothing,Integer})
    if spin isa Integer
        for _ in Base.OneTo(spin)
            f() || return
            ccall(:jl_cpu_pause, Cvoid, ())
            GC.safepoint()
        end
    end
    cond.task = current_task()
    @_assert cond.state[] == OWC_EMPTY
    cond.state[] = OWC_WAITING
    Threads.atomic_fence()  # prevent store-load reordering
    if f() # load
        wait()::Nothing
        @_assert !f()
    else
        state = Threads.atomic_cas!(cond.state, OWC_WAITING, OWC_EMPTY)
        if state === OWC_NOTIFYING
            # then we must "receive" the `schedule` call
            wait()::Nothing
            @_assert !f()
        else
            @_assert !f()
        end
        @_assert state in (OWC_WAITING, OWC_NOTIFYING)
    end
    cond.state[] = OWC_EMPTY
    cond.task = nothing
    return
end

"""
    OneWayObservable{T}(x::T)

Single-reader single-writer observable-ish.
"""
struct OneWayObservable{T}
    value::Threads.Atomic{T}
    _pads::NTuple{ATOMICS_NPADS,Threads.Atomic{T}}
    cond::OneWayCondition
end

function OneWayObservable{T}(x::T) where {T}
    value, _pads = cache_aligned_atomic(x)
    return OneWayObservable{T}(value, _pads, OneWayCondition())
end

@inline Base.getindex(o::OneWayObservable) = o.value[]

@inline function Base.setindex!(o::OneWayObservable{T}, v::T) where {T}
    o.value[] = v
    notify(o.cond)
end

waitif(f::F, o::OneWayObservable, spin::Union{Nothing,Integer}) where {F} =
    waitif(() -> f(o.value[]), o.cond, spin)

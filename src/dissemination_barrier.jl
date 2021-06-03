sense_parity_states(n) = RecordArrays.fill((sense = true, parity = 0), n; align = 64)

struct DisseminationBarrier <: Barriers.DisseminationBarrier
    n::Int
    flags::Array{OneWayObservable{Bool},3}
    locals::typeof(sense_parity_states(1))
end

DisseminationBarrier(n::Integer) = DisseminationBarrier(
    n,
    [OneWayObservable{Bool}(false) for _ in 1:ceillog2(n), _ in 1:n, _ in 1:2],
    sense_parity_states(n),
)

function inc_sense_parity!(state)
    parity = state.parity[]
    sense = state.sense[]
    if parity == 1
        state.sense[] = !sense
    end
    state.parity[] = 1 - parity
    return sense, parity
end

function prev_sense_parity(state)
    parity = 1 - state.parity[]
    sense = state.sense[]
    return ((parity == 1 ? !sense : sense), parity)
end

function Barriers.cycle!(
    handle::BarrierHandle{DisseminationBarrier},
    spin::Union{Nothing,Integer} = nothing,
)
    i = handle.i
    barrier = handle.barrier

    sense, parity = inc_sense_parity!(view(barrier.locals, handle.i))

    shift = 1
    for flags in eachrow(@view barrier.flags[:, :, parity+1])
        @_assert flags[i][] != sense
        flags[i][] = sense

        j = i - shift
        if j <= 0
            j += lastindex(flags)
        end
        shift *= 2

        waitif(x -> x != sense, flags[j], spin)
        @_assert flags[j][] == sense
    end
end

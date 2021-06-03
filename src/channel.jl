mutable struct Channel{T}
    value::T
    isset::Bool
    moretakers::Bool
    waiters::Vector{OneWayCondition}
    lock::ReentrantLock
end

function _tryput!(channel, value)
    sender = nothing
    receiver = nothing
    lock(channel.lock)
    try
        if channel.isset
            @assert !channel.moretakers
            todelete = Int[]
            for (i, w) in pairs(channel.waiters)
                if w.task === current_task()
                    if Atomic.cas!(w.state, OWC_EMPTY, OWC_WAITING) === OWC_EMPTY
                        sender = w
                        break
                    end
                elseif w.state[] === OWC_EMPTY
                    if Atomic.cas!(w.state, OWC_EMPTY, OWC_CLOSED) === OWC_EMPTY
                        push!(todelete, i)
                    end
                end
            end
            deleteat!(channel.waiters, todelete)
            if sender === nothing
                sender = OneWayCondition()
                sender.task = current_task()
                push!(channel.waiters, sender)
            end
        else
            if channel.moretakers
                todelete = Int[]
                for (i, w) in pairs(channel.waiters)
                    if Atomic.cas!(w.state, OWC_WAITING, OWC_WAITING) === OWC_EMPTY
                        sender = w
                        break
                    end
                end
            else
                channel.isset = true
                channel.value = value
            end
        end
    finally
        unlock(channel.lock)
    end
end

function _trytake!(channel)
    lock(channel.lock)
    try
        if channel.isset
            channel.isset = false
            return Some(channel.value)
        end
        for waiter in channel.waiters
        end
    finally
        unlock(channel.lock)
    end
end

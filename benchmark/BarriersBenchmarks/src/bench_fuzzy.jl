module BenchFuzzy

import LinearAlgebra
using Barriers
using BenchmarkTools
using UnPack: @unpack

function mul_naive!(
    y::AbstractVector,
    A::AbstractMatrix,
    x::AbstractVector,
    a = true,
    b = false,
)
    (axes(y, 1) == axes(A, 1) && axes(A, 2) == axes(x, 1)) || throw(DimensionMismatch())
    for i in axes(A, 1)
        s = zero(eltype(y))
        @simd for j in axes(A, 2)
            s += @inbounds A[i, j] * x[j]  # A is adjoint or transpose
        end
        y[i] = s * a + y[i] * b
    end
    return y
end

function sim_seq(model, niters, mul! = mul_naive!)
    @unpack f, g, A, B, C, x0, y0 = model
    x1 = copy(x0)
    x2 = similar(x0)
    y1 = copy(y0)
    y2 = similar(y0)
    for _ in 1:niters
        mul!(x2, A, x1)
        mul!(y2, C, x1)
        mul!(y2, B, y1, true, true)
        x2 .= f.(x2)
        y2 .= g.(y2)
        x1, x2 = x2, x1
        y1, y2 = y2, y1
    end
    return (x1, y1)
end

function sim_parallel_fuzzy(
    model,
    niters,
    bx,
    by,
    parallel_foreach,
    spin,
    mul! = mul_naive!,
)
    @assert length(bx) == length(by)
    @unpack f, g, A, B, C, x0, y0 = model
    x1 = copy(x0)
    x2 = similar(x0)
    y1 = copy(y0)
    y2 = similar(y0)
    xs = (x1, x2)
    ys = (y1, y2)

    ntasks = length(bx)
    xchunks = collect(Iterators.partition(eachindex(x0), cld(length(x0), ntasks)))
    ychunks = collect(Iterators.partition(eachindex(y0), cld(length(y0), ntasks)))
    @assert length(xchunks) == length(ychunks) == ntasks
    parallel_foreach(1:ntasks) do i
        for t in 1:niters
            local x1 , x2 , y1 , y2
            if isodd(t)
                x1, x2 = xs
                y1, y2 = ys
            else
                x2, x1 = xs
                y2, y1 = ys
            end
            @views begin
                xl = x2[xchunks[i]]
                yl = y2[ychunks[i]]
                Al = A[xchunks[i], :]
                Bl = B[ychunks[i], :]
                Cl = C[ychunks[i], :]
            end
            mul!(xl, Al, x1)
            t == 1 || depart!(by[i], spin)
            mul!(yl, Cl, x1)
            xl .= f.(xl)
            arrive!(bx[i])  # => x1 writable, x2 readable
            mul!(yl, Bl, y1, true, true)
            yl .= g.(yl)
            arrive!(by[i])  # => y1 writable, y2 readable
            depart!(bx[i], spin)
        end
    end

    return (x1, y1)
end

function sim_parallel(model, niters, b, parallel_foreach, spin, mul! = mul_naive!)
    @unpack f, g, A, B, C, x0, y0 = model
    x1 = copy(x0)
    x2 = similar(x0)
    y1 = copy(y0)
    y2 = similar(y0)
    xs = (x1, x2)
    ys = (y1, y2)

    ntasks = length(b)
    xchunks = collect(Iterators.partition(eachindex(x0), cld(length(x0), ntasks)))
    ychunks = collect(Iterators.partition(eachindex(y0), cld(length(y0), ntasks)))
    @assert length(xchunks) == length(ychunks) == ntasks
    parallel_foreach(1:ntasks) do i
        for t in 1:niters
            local x1 , x2 , y1 , y2
            if isodd(t)
                x1, x2 = xs
                y1, y2 = ys
            else
                x2, x1 = xs
                y2, y1 = ys
            end
            @views begin
                xl = x2[xchunks[i]]
                yl = y2[ychunks[i]]
                Al = A[xchunks[i], :]
                Bl = B[ychunks[i], :]
                Cl = C[ychunks[i], :]
            end
            mul!(xl, Al, x1)
            xl .= f.(xl)
            mul!(yl, Cl, x1)
            mul!(yl, Bl, y1, true, true)
            yl .= g.(yl)
            cycle!(b[i], spin)
        end
    end

    return (x1, y1)
end

function sim_parallel_nobarrier(model, niters, ntasks, parallel_foreach, mul! = mul_naive!)
    @unpack f, g, A, B, C, x0, y0 = model
    x1 = copy(x0)
    x2 = similar(x0)
    y1 = copy(y0)
    y2 = similar(y0)
    xs = (x1, x2)
    ys = (y1, y2)

    xchunks = collect(Iterators.partition(eachindex(x0), cld(length(x0), ntasks)))
    ychunks = collect(Iterators.partition(eachindex(y0), cld(length(y0), ntasks)))
    @assert length(xchunks) == length(ychunks) == ntasks
    for t in 1:niters
        parallel_foreach(1:ntasks) do i
            local x1 , x2 , y1 , y2
            if isodd(t)
                x1, x2 = xs
                y1, y2 = ys
            else
                x2, x1 = xs
                y2, y1 = ys
            end
            @views begin
                xl = x2[xchunks[i]]
                yl = y2[ychunks[i]]
                Al = A[xchunks[i], :]
                Bl = B[ychunks[i], :]
                Cl = C[ychunks[i], :]
            end
            mul!(xl, Al, x1)
            xl .= f.(xl)
            mul!(yl, Cl, x1)
            mul!(yl, Bl, y1, true, true)
            yl .= g.(yl)
        end
    end

    return (x1, y1)
end

function parallel_foreach_static(f, xs)
    Threads.@threads :static for x in xs
        f(x)
    end
end

function parallel_foreach_dynamic(f, xs)
    tasks = empty!(Vector{Task}(undef, length(xs)))
    for x in xs
        t = Threads.@spawn f(x)
        push!(tasks, t)
    end
    foreach(wait, tasks)
end

function random_model(n, m, g = 1.5)
    At = (g / √n) .* rand(n, n)
    Bt = (g / √m) .* rand(m, m)
    Ct = (g / √n) .* rand(n, m)
    return (
        A = At',
        B = Bt',
        C = Ct',
        x0 = randn(n),
        y0 = randn(m),
        f = tanh,
        g = tanh,
        # ...
    )
end

const CACHE = Ref{Any}(nothing)

function setup(;
    n = 2^9,
    m = 2^10,
    niters = 1000,
    ntasks = Threads.nthreads(),
    spin = nothing,
    nbranches = 2,
)
    @debug "BenchFuzzy.setup: n=$n m=$m niters=$niters ntasks=$ntasks spin=$spin nbranches=$nbranches"

    CACHE[] = random_model(n, m)

    suite = BenchmarkGroup()

    suite["seq"] = @benchmarkable sim_seq(CACHE[], $niters)
    suite["blas"] = @benchmarkable sim_seq(CACHE[], $niters, LinearAlgebra.mul!)

    for (label, barrier) in [
        # Fuzzy barriers:
        ("tree", TreeBarrier{nbranches}),
        ("flat-tree", FlatTreeBarrier{nbranches}),
        ("centralized", CentralizedBarrier),
    ]
        s1 = suite[label] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel_fuzzy(
            CACHE[],
            $niters,
            $barrier($ntasks),
            $barrier($ntasks),
            parallel_foreach_static,
            $spin,
        )
        s1["dynamic"] = @benchmarkable sim_parallel_fuzzy(
            CACHE[],
            $niters,
            $barrier($ntasks),
            $barrier($ntasks),
            parallel_foreach_dynamic,
            $spin,
        )
    end

    for (label, barrier) in [
        # Non-fuzzy barriers:
        ("flat-tree-no-fuzzy", FlatTreeBarrier{nbranches}),
        ("centralized-no-fuzzy", CentralizedBarrier),
        ("dissemination", DisseminationBarrier),
    ]
        s1 = suite[label] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel(
            CACHE[],
            $niters,
            $barrier($ntasks),
            parallel_foreach_static,
            $spin,
        )
        s1["dynamic"] = @benchmarkable sim_parallel(
            CACHE[],
            $niters,
            $barrier($ntasks),
            parallel_foreach_dynamic,
            $spin,
        )
    end

    let s1 = suite["nobarrier"] = BenchmarkGroup()
        s1["static"] = @benchmarkable sim_parallel_nobarrier(
            CACHE[],
            $niters,
            $ntasks,
            parallel_foreach_static,
        )
        s1["dynamic"] = @benchmarkable sim_parallel_nobarrier(
            CACHE[],
            $niters,
            $ntasks,
            parallel_foreach_static,
        )
    end

    return suite
end

function clear()
    CACHE[] = nothing
end

end  # module

module TestBenchSmoke

using Test
using BarriersBenchmarks: clear, setup_smoke

function test_bench_smoke()
    try
        local suite
        @test (suite = setup_smoke()) isa Any
        @test run(suite) isa Any
    finally
        clear()
    end
end

end  # module

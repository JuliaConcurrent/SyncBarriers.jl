module TestUtils

using Test
using SyncBarriers.Internal: ceillog2

function test_ceillog2()
    xs = 1:2^10
    @test ceillog2.(xs) == ceil.(Int, log2.(xs))
end

end  # module

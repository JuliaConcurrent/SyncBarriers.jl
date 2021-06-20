module TestDoctest

import SyncBarriers
using Documenter: doctest
using Test

function test()
    doctest(SyncBarriers)
end

end  # module

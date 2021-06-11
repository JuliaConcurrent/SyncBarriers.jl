module TestDoctest

import Barriers
using Documenter: doctest
using Test

function test()
    doctest(Barriers)
end

end  # module

module TestAqua

import Aqua
import Barriers

test() = Aqua.test_all(Barriers; unbound_args = false)

end  # module

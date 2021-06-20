module TestAqua

import Aqua
import SyncBarriers

test() = Aqua.test_all(SyncBarriers; unbound_args = false)

end  # module

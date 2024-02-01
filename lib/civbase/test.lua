
local mul, err = package.loadlib("./libcivbase.so", "l_mul")

local v = math.floor(2 ^ 33) + 3
assert(mul(3, 3) == 9)
assert(mul(v, v) == 51539607561) -- overflow

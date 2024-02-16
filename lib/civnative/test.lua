
local mulOver, err = package.loadlib("./civnative.so", "l_mulOver")
assert(mulOver, err or '')

local v = math.floor((2 ^ 33) + 12)
print("v", v)
assert(mulOver(3, 3) == 9)
print("expect ", 51539607561, 'got', mulOver(v, v + 3))
assert(mulOver(v, v) == 51539607561) -- overflow

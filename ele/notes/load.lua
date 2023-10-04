

local three, err = load('return 1 + 2')
print('three', three(), err)
assert(not err)
assert(3 == three())

assert(not a)
local env = {}
local setA, err = load('a = 7', 'env', 't', env)
assert(not a)
setA()
assert(not a)
print('env.a', env.a)
assert(env.a)

local function eval(s, env, name)
  assert(s); assert(type(env) == 'table')
  local info = debug.getinfo(2)
  name = name or string.format('%s:%s', info.source, info.currentline)
  return load(s, name, 't', env), name
end

local e, name = eval('b = 12; c = a + b', env)
print(name)
e()
print('b, c', env.b, env.c)
assert(env.c == 19)

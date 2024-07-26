local lines = require'lines'
local ds = require'ds'
local testing = require'lines.testing'
local test, assertEq, assertMatch, assertErrorPat; ds.auto'civtest'
local U3File = require'lines.U3File'

local push = table.insert

local loadu3s = function(f)
  local pos, t = f:seek'cur', {}
  assert(pos)
  f:seek'set'
  for u3 in f:lines(3) do push(t, (('>I3'):unpack(u3))) end
  f:seek('set', pos) -- reset
  return t
end

test('U3File', function()
  local u = U3File:create()
  u[1] = 11; u[2] = 22; u[3] = 33
  assertEq(11, u[1])
  assertEq(22, u[2])
  assertEq(33, u[3]); assertEq(nil, rawget(u, 3))
  assertEq({11, 22, 33}, loadu3s(u.f))
  assertEq(11, u[1]) -- testing loadu3s
  assertEq(3, #u)

  u[2] = 20; assertEq({11, 20, 33}, loadu3s(u.f))
  assertEq(20, u[2])
  assertEq(33, u[3])

  u[1] = 10; u[4] = 44; u[5] = 55
  assertEq({10, 20, 33, 44, 55}, loadu3s(u.f))
  assertEq(10, u[1])
  assertEq(55, u[5])

  local l = {}; for i, v in ipairs(u) do l[i] = v end
  assertEq({10, 20, 33, 44, 55}, l)
  assertEq(5, #u)
end)

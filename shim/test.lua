
local T = require'civtest'
local M = require'shim'
local parse = M.parse


T.test('parse', function()
  T.assertEq({'a', 'b', c='42'}, parse{'a', '--c=42', 'b'})
  T.assertEq({c={'1', '2'}}, parse{'--c=1', '--c=2'})
  T.assertEq({c={'1', '2', '3'}}, parse{'--c=1', '--c=2', '--c=3'})
end)

T.test('list', function()
  T.assertEq({'12'}, M.list('12'))
  T.assertEq({'12', '34'}, M.list({'12', '34'}))
  T.assertEq({'12', '34'}, M.listSplit({'12 34'}))
  T.assertEq({'12', '34'}, M.listSplit('12  \n  34'))
  T.assertEq({'12', '34', '56', '78'},
             M.listSplit({'12  \n  34', '56 78'}))
end)

T.test('duck', function()
  T.assertEq(true, M.boolean(true))
  T.assertEq(true, M.boolean'true')
  T.assertEq(true, M.boolean'yes')

  T.assertEq(false, M.boolean(false))
  T.assertEq(false, M.boolean'false')
  T.assertEq(false, M.boolean(nil))

  -- new
  local function add1(v) return v + 1 end
  T.assertEq(5, M.new(add1, 4))

  local t = setmetatable({}, {})
  assert(t == M.new(nil, t))

  local mt = setmetatable({}, {
    __call=function(ty_, t) return setmetatable(t, ty_) end
  })
  local t = {}; local res = M.new(mt, t)
  assert(t == t)
  assert(getmetatable(t) == mt)
end)

assert(M.isExe())
M{exe=function(t)
  assert(t.test == 'test.lua', tostring(t.test))
end}

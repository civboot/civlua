
local pkg = require'pkg'
local T = pkg'civtest'
local M = pkg'shim'
local p, ps, e = M.parse, M.parseStr, M.expand

T.test('parse', function()
  T.assertEq({'a', 'b', c='42'},  ps'a --c=42 b')
  T.assertEq({c={'1', '2'}},      ps'--c=1 --c=2')
  T.assertEq({c={'1', '2', '3'}}, ps'--c=1 --c=2 --c=3')

  T.assertEq({a=true, b=true, c='foo'}, p{'-ab', '--c=foo'})
end)

T.test('parseStr', function()
  T.assertEq({'a', 'b', c='42'}, ps'a b --c=42')
  T.assertEq({c={'1', '2'}},     ps'--c=1   --c=2')
  T.assertEq({a=true, b=true, c='foo'}, ps'-ab --c=foo')
end)

T.test('expand', function()
  T.assertEq({'a', 'b', '--c=42'},           e{'a', 'b', c=42})
  T.assertEq({'a', 'b', '--c=42', '--d=hi'}, e(ps'a b --d=hi --c=42'))
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
  T.assertEq(nil, M.boolean(nil))

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

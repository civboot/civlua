G.METATY_CHECK = true

local ge = {}; for k in pairs(_G) do table.insert(ge, k) end
local M = require'metaty'
assert(M.getCheck())

local mty, split = M, M.split

local add, sfmt = table.insert, string.format

local Tm = mod'Tm'

local function test(name, fn)
  print('# Test', name)
  fn()
end

local function assertEq(expect, result)
  if M.eq(expect, result) then return end
  local f = Fmt:pretty{}
  print("! EXPECT: ", tostring(expect))
  print("! RESULT: ", tostring(result))
  error'Values not mty.eq'
end

local function assertMatch(expectPat, result)
  if not result:match(expectPat) then
    M.errorf('Does not match pattern:\nPattern: %q\n Result:  %s',
           expectPat, result)
  end
end

local function assertErrorPat(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then M.errorf('! No error received, expected: %q', errPat) end
  if not err:find(errPat, 1, plain) then M.errorf(
    '! Expected error %q but got %q', errPat, err
  )end
end

test('string.concat', function()
  assertEq('',   string.concat())
  assertEq('a',  string.concat('a'))
  assertEq('ab', string.concat('a', 'b'))
end)


local function splitT(...)
  local t = {}; for st, item in split(...) do
    add(t, {item, st.si, st.ei})
  end
  return t
end
local LINES = '\nhi\n\nthere\nyou\n', '\n'

test('split', function()
  assertEq({
    {'hi',    1, 2},
    {'there', 4, 8},
    {'jane',  10, 13},
  }, splitT('hi there\njane'))

  assertEq({
    {'',      1,  0},
    {'hi',    2,  3},
    {'',      5,  4},
    {'there', 6,  10},
    {'you',   12, 14},
    {'',      16, 15},
  }, splitT(LINES, '\n'))
end)

test('ty', function()
  assert('string' == M.ty('hi'))
  assert('number' == M.ty(4))
  assert('table'  == M.ty({}))
  local mt = {}
  assert(mt       == M.ty(setmetatable({}, mt)))
end)

test('name', function()
  assertEq('string', M.tyName('string'))
  assertEq('string', M.tyName(M.ty('hi')))

  assertEq('number', M.tyName('number'))
  assertEq('number', M.tyName(M.ty(4)))

  assertEq('table',  M.tyName('table'))
  assertEq('table',  M.tyName(M.ty({})))

  local mt = {__name='F'}
  assertEq('F', M.tyName(mt))
  assertEq('F', M.tyName(M.ty(setmetatable({}, mt))))

  assertEq('string', M.name'hi')
  assertEq('table',  M.name{})
  assertEq('foo',    M.name(setmetatable({}, {__name='foo'})))

  Tm.A = mty'A'
  assertEq('Tm.A',   M.name(Tm.A))
  assertEq('Tm.A',   PKG_NAMES[Tm.A])
end)

test('record', function()
  local A = M'A'{'a2[any]', 'a1[any]'}
  local B = mty'B'{
    'b1[number]', 'b2[number] (default=32)',
    'a[A]'
  }
  B.b2 = 32

  local a = A{a1='hi', a2=5}
  assert(A == getmetatable(a))
  assertEq('[any]', A.__fields.a1)
  assertEq('[any]', getmetatable(a).__fields.a2)
  assert(A == M.ty(a))
  assert('hi' == a.a1); assert(5 == a.a2)
  a.a2 = 4;             assert(4 == a.a2)

  local b = B{b1=5, a=a}
  assert(B == getmetatable(b))
  assertEq(5, b.b1); assertEq(32, b.b2) -- default
  b.b2 = 7;          assertEq(7, b.b2)

  assertErrorPat('A does not have field a3',
    function() local x = a.a3 end)
  assertErrorPat('A does not have field a3',
    function() a.a3 = 7 end)

  A.meth = function() end
  assertEq(A.meth, M.getmethod(A,   'meth'))
  assertEq(A.meth, M.getmethod(A{}, 'meth'))
  assertEq(nil,    M.getmethod(A{}, 'does-not-exist'))
end)

test('record maybe', function()
  local A = mty'A' {'a1[string]', 'a2[number]'}

  local a = A{a1='hi'}
    assertEq('hi', a.a1);   assertEq(nil, a.a2);
    assertEq(A{a1='hi'}, a)
  a.a2 = 4;   assertEq(4, a.a2);
              assertEq(A{a1='hi', a2=4}, a)
  a.a2 = nil; assertEq(nil, a.a2)
end)

test('extend type', function()
  local A = mty'A' {'a1[string]', 'a2[number]'}
  local a = A{}; assertEq('A', a.__name)

  local B = M.extend(A, 'B', {'b1[string]', b1='default'})
  assertEq('B', B.__name)
  local b = B{}; assertEq('B', b.__name)
  assertEq('default', b.b1)
end)

test('globals', function()
  local gr = {}; for k in pairs(_G) do table.insert(gr, k) end
  table.sort(ge); table.sort(gr);
  assertEq(ge, gr)
end)

-- test('fmtFile', function()
--   local f = Fmt{file=io.open('.out/TEST', 'w+')}
--   f:fmt{1, 2, z='bob', a='hi'}
--   f.file:flush(); f.file:seek'set'
--   assertEq('{1,2 :: a="hi" z="bob"}', f.file:read'a')
--   f.file:close()
-- end)

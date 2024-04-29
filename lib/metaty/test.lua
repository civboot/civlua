METATY_CHECK = true

local ge = {}; for k in pairs(_G) do table.insert(ge, k) end
local pkg = require'pkg'
local M = pkg'metaty'
assert(M.getCheck())

local ty, tyName, record2, split, Fmt2; pkg.auto'metaty'

local add, sfmt = table.insert, string.format

-- test('lines', function()
--   assertEq({'a', 'bc', '', 'd'}, lines('a\nbc\n\nd'))
-- end)
local function test(name, fn) print('# Test', name) fn() end

local function assertEq(expect, result)
  if M.eq(expect, result) then return end
  local f = Fmt2:pretty{}
  add(f, "! Values not equal:")
  add(f, "\n! EXPECT: "); f(expect)
  add(f, "\n! RESULT: "); f(result); add(f, '\n')
  error(table.concat(f), 2)
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
  assert('string' == ty('hi'))
  assert('number' == ty(4))
  assert('table'  == ty({}))
  local mt = {}
  assert(mt       == ty(setmetatable({}, mt)))
end)

test('tyName', function()
  assertEq('string', tyName('string'))
  assertEq('string', tyName(ty('hi')))

  assertEq('number', tyName('number'))
  assertEq('number', tyName(ty(4)))

  assertEq('table',  tyName('table'))
  assertEq('table',  tyName(ty({})))

  local mt = {__name='F'}
  assertEq('F', tyName(mt))
  assertEq('F', tyName(ty(setmetatable({}, mt))))
end)

test('record', function()
  local A = record2'A'{'a2[any]', 'a1[any]'}
  local B = record2'B'{
    'b1[number]', 'b2[number] (default=32)',
    'a[A]'
  }
  B.b2 = 32

  local a = A{a1='hi', a2=5}
  assert(A == getmetatable(a))
  assertEq('[any]', A.__fields.a1)
  assertEq('[any]', getmetatable(a).__fields.a2)
  assert(A == ty(a))
  assert('hi' == a.a1); assert(5 == a.a2)
  assertEq('A{a2=5, a1="hi"}', M.tostring(a))
  a.a2 = 4;             assert(4 == a.a2)

  local b = B{b1=5, a=a}
  assert(B == getmetatable(b))
  assertEq(5, b.b1); assertEq(32, b.b2) -- default
  b.b2 = 7;          assertEq(7, b.b2)
  assertEq('B{b1=5, b2=7, a=A{a2=4, a1="hi"}}', M.tostring(b))

  print('!! expect err', a, getmetatable(a).__fields)
  assertErrorPat('A does not have field a3',
    function() local x = a.a3 end)
  assertErrorPat('A does not have field a3',
    function() a.a3 = 7 end)
end)

test('record maybe', function()
  local A = record2'A' {'a1[string]', 'a2[number]'}

  local a = A{a1='hi'}
    assertEq('hi', a.a1);   assertEq(nil, a.a2);
    assertEq(A{a1='hi'}, a)
  a.a2 = 4;   assertEq(4, a.a2);
              assertEq(A{a1='hi', a2=4}, a)
  a.a2 = nil; assertEq(nil, a.a2)
end)

test("tostring", function()
  local toStr = M.tostring
  assertEq('"a123"',    toStr("a123"))
  assertEq('"123"',     toStr("123"))
  assertEq('"abc def"', toStr("abc def"))
  assertEq('423',       toStr(423))
  assertEq('1A',        toStr(26, Fmt2{numfmt='%X'}))
  assertEq('true',      toStr(true))
  assertMatch('Fn@.*/metaty%.lua:%d+', toStr(M.errorf))
  assertMatch('{hi=4}', toStr{hi=4})
  assertMatch('{hi=4}',
    toStr(setmetatable({hi=4}, {}))
  )
end)

test("fmt", function()
  assertEq("{1, 2, 3}", M.tostring{1, 2, 3})

  local t = {1, 2}; t[3] = t
  assertMatch('{!max depth reached!}',    M.tostring(t))

  assertEq( [[{baz="boo", foo="bar"}]],
    M.tostring{foo="bar", baz="boo"})
  local result = M.tostring({a=1, b=2, c=3}, M.Fmt2:pretty{})
  assertEq('{\n  a=1,\n  b=2,\n  c=3\n}', result)
  assertEq('{1, 2, a=12}', M.tostring{1, 2, a=12})
  assertEq('{["a b"]=5}', M.tostring{['a b'] = 5})
  assertEq('{\n  1, 2, \n  a=12\n}',
           M.tostring({1, 2, a=12}, M.Fmt2:pretty{}))
end)

test('format', function()
  assertEq('hi "Bob"! Goodbye',
    M.format('hi %q! %s', 'Bob', 'Goodbye'))
  assertEq('running point: {x=3, y=7}...',
    M.format('%s point: %q...', 'running', {x=3, y=7}))
end)

test('globals', function()
  local gr = {}; for k in pairs(_G) do table.insert(gr, k) end
  table.sort(ge); table.sort(gr);
  assertEq(ge, gr)
end)

test('doc', function()
--    assertEq([[
-- function [Fn@lib/metaty/metaty.lua:10]
--   isEnv"MY_VAR" -> boolean (environment variable)
--     true: 'true' '1'    false: 'false' '0' '']],
-- M.help(M.isEnv))
  local A = M.doc'demo record and some fields.'
  (record2'A') {
    [[a1[number]: pick number
    now with newline!]],
    [[a2[string]: and a string]],
  }
-- assertMatch(([=[
-- %[A%]: demo record and some fields.
-- 
--   Fields:
--     a1 %[number default=3%]: pick number,
--         now with newline!
--     a2 %[string default=nil%]: and a string
-- %s*
--   metatable=%b{}
-- %s*
--   Members
--     __doc: string
--     __fdocs: table
--     __fields: table
--     __maybes: table
--     __name: string
-- %s*
--   Methods
--     __fmt      %s+: function %b[]
--     __index    %s+: function %b[]
--     __missing  %s+: function %b[]
--     __newindex %s+: function %b[]
--     __tostring %s+%(DOC%) : function %b[]
-- ]=]):sub(1, -2), -- remove newline
-- M.help(A))
end)

-- test('fmtFile', function()
--   local f = Fmt2{file=io.open('.out/TEST', 'w+')}
--   f:fmt{1, 2, z='bob', a='hi'}
--   f.file:flush(); f.file:seek'set'
--   assertEq('{1,2 :: a="hi" z="bob"}', f.file:read'a')
--   f.file:close()
-- end)

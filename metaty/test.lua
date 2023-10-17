METATY_CHECK = true

local ge = {}; for k in pairs(_G) do table.insert(ge, k) end
local M = require'metaty'
assert(M.getCheck())

local ty, tyName, tyCheck, record;
local fmt, Fmt, FmtSet, split
M.lrequire'metaty' -- includes undefined locals

local add, sfmt = table.insert, string.format

-- test('lines', function()
--   assertEq({'a', 'bc', '', 'd'}, lines('a\nbc\n\nd'))
-- end)
local function test(name, fn) print('# Test', name) fn() end

local function assertEq(expect, result)
  if M.eq(expect, result) then return end
  local f = M.Fmt{set=FmtSet{ pretty=true }}
  add(f, "! Values not equal:")
  add(f, "\n! EXPECT: "); f:fmt(expect)
  add(f, "\n! RESULT: "); f:fmt(result); add(f, '\n')
  error(table.concat(f))
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

  assert(not M._isTyErrMsg('string'))
  assertEq('"null" is not a native type', M._isTyErrMsg('null'))
  assertEq('boolean cannot be used as a type',
           M._isTyErrMsg(true))
end)

test('record', function()
  local A = record('A')
    :field('a2', 'number')
    :field('a1', 'string')
  local B = record('B')
    :field('b1', 'number')
    :field('b2', 'number', 32)
    :field('a', A)

  local a = A{a1='hi', a2=5}
  assert(A == getmetatable(a))
  assert(A == ty(a))
  assert('hi' == a.a1); assert(5 == a.a2)
  assertEq('A{a2=5 a1="hi"}', tostring(a))
  a.a2 = 4;             assert(4 == a.a2)

  local b = B{b1=5, a=a}
  assert(B == getmetatable(b))
  assertEq(5, b.b1); assertEq(32, b.b2) -- default
  b.b2 = 7;          assertEq(7, b.b2)
  assertEq('B{b1=5 b2=7 a=A{a2=4 a1="hi"}}', tostring(b))

  assertEq(A,   tyCheck(A, A))
  assertEq(B,   tyCheck(B, B))
  assertEq(nil, tyCheck(A, B))

  assertErrorPat('a1="fail"', function()
    assertEq(A{a1='fail', a2=5}, a)
  end)
  assertErrorPat('A does not have field a3',
    function() local x = a.a3 end)
  assertErrorPat('A does not have field a3',
    function() a.a3 = 7 end)

end)

test('record maybe', function()
  local A = record('A')
    :field('a1',      'string')
    :fieldMaybe('a2', 'number')

  local a = A{a1='hi'}
    assertEq('hi', a.a1);   assertEq(nil, a.a2);
    assertEq(A{a1='hi'}, a)
  a.a2 = 4;   assertEq(4, a.a2);
              assertEq(A{a1='hi', a2=4}, a)
  a.a2 = nil; assertEq(nil, a.a2)
end)

test("safeToStr", function()
  local safeToStr = M.safeToStr
  assertEq('"a123"',      safeToStr("a123"))
  assertEq('"123"',     safeToStr("123"))
  assertEq('"abc def"', safeToStr("abc def"))
  assertEq('423',       safeToStr(423))
  assertEq('1A',        safeToStr(26, FmtSet{num='%X'}))
  assertEq('true',      safeToStr(true))
  assertMatch('Fn@.*/metaty%.lua:%d+', safeToStr(M.errorf))
  assertMatch('Tbl@0x[a-f0-9]+', safeToStr({hi=4}))
  assertMatch('?@0x[a-f0-9]+',
    safeToStr(setmetatable({hi=4}, {}))
  )
  assertMatch('?{...}',
    safeToStr(setmetatable({hi=4}, {
      __tostring=function() return 'not called' end
    }))
  )
end)

test("fmt", function()
  local r = fmt({1, 2, 3})
  assertEq("{1,2,3}", r)

  local t = {1, 2}; t[3] = t
  assertMatch('!ERROR!.*stack overflow', fmt(t, FmtSet{safe=true}))
  assertMatch('{1,2,RECURSE%[Tbl@0x%w+%]}', fmt(t, FmtSet{recurse=false}))

  assertEq([[{baz="boo" foo="bar"}]], fmt({foo="bar", baz="boo"}))
  local result = fmt({a=1, b=2, c=3}, FmtSet{pretty=true})
  assertEq('{\n  a=1\n  b=2\n  c=3\n}', result)
  assertEq('{1,2 :: a=12}', fmt({1, 2, a=12}))
  assertEq('{["a b"]=5}', fmt({['a b'] = 5}))
end)

test('globals', function()
  local gr = {}; for k in pairs(_G) do table.insert(gr, k) end
  table.sort(ge); table.sort(gr);
  assertEq(ge, gr)
end)

test('doc', function()
assertEq([[
function [Fn@metaty/metaty.lua:10]
  isEnv"MY_VAR" -> boolean (environment variable)
    true: 'true' '1'    false: 'false' '0' '']],
M.help(M.isEnv))
  local A = M.doc'demo record and some fields.'
    (record'A')
    :field('a1', 'number', 3):fdoc'pick number,\
    now with newline!'
    :fieldMaybe('a2', 'string'):fdoc'and a string'
assertMatch(([=[
%[A%]: demo record and some fields.

  Fields:
    a1 %[number default=3%]: pick number,
        now with newline!
    a2 %[string default=nil%]: and a string
%s*
  metatable=%b{}
%s*
  Members
    __doc: string
    __fdocs: table
    __fields: table
    __maybes: table
    __name: string
%s*
  Methods
    __fmt      %s+: function %b[]
    __index    %s+: function %b[]
    __missing  %s+: function %b[]
    __newindex %s+: function %b[]
    __tostring %s+%(DOC%) : function %b[]
]=]):sub(1, -2), -- remove newline
M.help(A))
end)

test('fmtFile', function()
  local f = Fmt{file=io.open('out/TEST', 'w+')}
  f:fmt{1, 2, z='bob', a='hi'}
  f.file:flush(); f.file:seek'set'
  assertEq('{1,2 :: a="hi" z="bob"}', f.file:read'a')
  f.file:close()
end)

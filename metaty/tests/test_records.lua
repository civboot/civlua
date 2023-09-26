METATY_CHECK = true

local mty = require'metaty':grequire()
assert(mty.getCheck())

test('assertError', function()
  assertErrorPat('RESULT: 2', function() assertEq(1, 2) end)
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
  assertEq('A{a2=5 a1=hi}', tostring(a))
  a.a2 = 4;             assert(4 == a.a2)

  local b = B{b1=5, a=a}
  assert(B == getmetatable(b))
  assertEq(5, b.b1); assertEq(32, b.b2) -- default
  b.b2 = 7;          assertEq(7, b.b2)
  assertEq('B{b1=5 b2=7 a=A{a2=4 a1=hi}}', tostring(b))

  assertEq(A,   tyCheck(A, A))
  assertEq(B,   tyCheck(B, B))
  assertEq(nil, tyCheck(A, B))

  assertErrorPat('a1=fail', function()
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
  assertEq("a123",      safeToStr("a123"))
  assertEq('"123"',     safeToStr("123"))
  assertEq('"abc def"', safeToStr("abc def"))
  assertEq('423',       safeToStr(423))
  assertEq('1A',        safeToStr(26, FmtSet{num='%X'}))
  assertEq('true',      safeToStr(true))
  assertMatch('Fn@.*/metaty%.lua:%d+', safeToStr(mty.errorf))
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

  assertEq([[{baz=boo foo=bar}]], fmt({foo="bar", baz="boo"}))
  local result = fmt({a=1, b=2, c=3}, FmtSet{pretty=true})
  assertEq('{\n  a=1\n  b=2\n  c=3\n}', result)

  assertEq('{1,2 :: a=12}', fmt({1, 2, a=12}))
end)

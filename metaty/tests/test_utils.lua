METATY_CHECK = true

local mty = require'metaty':grequire()

-- test('lines', function()
--   assertEq({'a', 'bc', '', 'd'}, lines('a\nbc\n\nd'))
-- end)

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

  assert(not isTyErrMsg('string'))
  assertEq('"null" is not a native type', isTyErrMsg('null'))
  assertEq('boolean cannot be used as a type',
           isTyErrMsg(true))
end)



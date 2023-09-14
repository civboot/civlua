METATY_CHECK = true
local mty = require'metaty':grequire()

test('generic simple', function()
  local A = record'A'
    :generic'X'
    :field('x', g'X')

  assertEq('generic', A.__kind)
  assertEq(newGeneric, getmetatable(A).__call)
  assertEq(Any, A.__genvars['X'])

  local A_num = A{X='number'}
  assertEq(Any,      A.__genvars['X']) -- stays the same
  assertEq('number', A_num.__genvars['X'])

  local aNum = A_num{x=42}
  assertEq(42, aNum.x)
end)

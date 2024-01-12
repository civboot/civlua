METATY_CHECK = true

local pkg = require'pkg'
local mty = require'metaty'
local test, assertEq
mty.lrequire'civtest'

local decDistance, lcLe, lcGe, lcWithin
local forword, backword, findBack
local wordKind
mty.lrequire'rebuf.motion'

test('distance', function()
  assertEq(3, decDistance(1, 4))
  assertEq(2, decDistance(5, 1))
  assertEq(5, decDistance(5, 5))
end)

test('lc', function()
  assert(    lcLe(1,1,   1,3))
  assert(    lcLe(1,2,   1,3))
  assert(    lcLe(1,3,   1,3))
  assert(not lcLe(1,4,   1,3))

  assert(not lcGe(1,1,   1,3))
  assert(not lcGe(1,2,   1,3))
  assert(    lcGe(1,3,   1,3))
  assert(    lcGe(1,4,   1,3))

  assert(not lcWithin(1, 0,   1, 1,   1, 5))
  assert(    lcWithin(1, 1,   1, 1,   1, 5))
  assert(    lcWithin(1, 3,   1, 1,   1, 5))
  assert(    lcWithin(1, 5,   1, 1,   1, 5))
  assert(not lcWithin(1, 6,   1, 1,   1, 5))
  assert(not lcWithin(2, 3,   1, 1,   1, 5))

  assert(not lcWithin(1, 1,  1, 4,   3, 3))
  assert(not lcWithin(1, 3,  1, 4,   3, 3))
  assert(    lcWithin(1, 4,  1, 4,   3, 3))
  assert(    lcWithin(2, 4,  1, 4,   3, 3))
  assert(    lcWithin(3, 1,  1, 4,   3, 3))
  assert(    lcWithin(3, 3,  1, 4,   3, 3))
  assert(not lcWithin(3, 4,  1, 4,   3, 3))
  assert(not lcWithin(4, 1,  1, 4,   3, 3))
end)

test('wordKind', function()
  assertEq('let', wordKind('a'))
  assertEq('()',  wordKind('('))
  assertEq('()',  wordKind(')'))
  assertEq('sym', wordKind('+'))
end)

test('forword', function()
  assertEq(3, forword('a bcd'))
  assertEq(3, forword('  bcd'))
  assertEq(2, forword(' bcd'))
  assertEq(3, forword('--bcd'))
  assertEq(2, forword('a+ bcd'))
  assertEq(5, forword('+12 +de', 2))
end)

test('backword', function()
  assertEq(3,   backword('a bcd', 4))
  assertEq(3,   backword('  bcd', 4))
  assertEq(nil, backword('  bcd', 3))
end)

test('findBack', function()
  assertEq({7, 8},   {findBack('12 45 12 ', '12')})
  assertEq({1, 2},   {findBack('12 45 12 ', '12', 6)})
end)

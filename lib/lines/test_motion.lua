METATY_CHECK = true

local mty = require'metaty'
local ds  = require'ds'
local T = require'civtest'

local decDistance, lcLe, lcGe, lcWithin
local forword, backword, findBack
local wordKind
ds.auto'lines.motion'

T.distance = function()
  T.eq(3, decDistance(1, 4))
  T.eq(2, decDistance(5, 1))
  T.eq(5, decDistance(5, 5))
end

T.lc = function()
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
end

T.wordKind = function()
  T.eq('let', wordKind('a'))
  T.eq('()',  wordKind('('))
  T.eq('()',  wordKind(')'))
  T.eq('sym', wordKind('+'))
end

T.forword = function()
  T.eq(3, forword('a bcd'))
  T.eq(3, forword('  bcd'))
  T.eq(2, forword(' bcd'))
  T.eq(3, forword('--bcd'))
  T.eq(2, forword('a+ bcd'))
  T.eq(5, forword('+12 +de', 2))
end

T.backword = function()
  T.eq(3,   backword('a bcd', 4))
  T.eq(3,   backword('  bcd', 4))
  T.eq(nil, backword('  bcd', 3))
end

T.findBack = function()
  T.eq({7, 8},   {findBack('12 45 12 ', '12')})
  T.eq({1, 2},   {findBack('12 45 12 ', '12', 6)})
end

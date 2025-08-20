METATY_CHECK = true

local mty = require'metaty'
local ds  = require'ds'
local T = require'civtest'

local decDistance, lcLe, lcGe, lcWithin
local forword, backword, findBack
local wordKind, pathKind, getRange
local topLeft
ds.auto'lines.motion'

T.distance = function()
  T.eq(3, decDistance(1, 4))
  T.eq(2, decDistance(5, 1))
  T.eq(5, decDistance(5, 5))
end

T.topLeft = function()
  T.eq({1,1}, {topLeft(1, nil, 5, nil)})
  T.eq({2,1}, {topLeft(2, nil, 3, nil)})
  T.eq({2,5}, {topLeft(7, 1, 2, 5)})
  T.eq({2,5}, {topLeft(2, 5, 7, 7)})
  T.eq({2,5}, {topLeft(2, 5, 7, 3)})
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

T.pathKind = function()
  T.eq('path', pathKind'a')
  T.eq('path', pathKind'/')
  T.eq('path', pathKind'-')
  T.eq('()',   pathKind'(')
  T.eq('()',   pathKind')')
  T.eq('sym',  pathKind'+')
end

local function forpath(s, begin)
  return forword(s, begin, pathKind)
end
local function backpath(s, end_)
  return backword(s, end_, pathKind)
end

T.forpath = function()
  T.eq(3, forpath('a bcd'))
  T.eq(6, forpath('a/bcd"  '))
  T.eq(8, forpath('a/b/c.d" '))
end

T.backpath = function()
  T.eq(3, backpath('a b/c/d', 7))
end

local pathRange = function(s, i) return getRange(s, i, pathKind) end
T.getRange = function()
  T.eq({3, 5}, {pathRange(' "a/b is the path" ', 4)})
end

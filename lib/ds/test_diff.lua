local mty = require'metaty'
local ds = require'ds'
local Iter = require'ds.Iter'
local test, assertEq; local T = ds.auto'civtest'
local Keep, Change, toChanges; ds.auto'vcds'
local add, concat = table.insert, table.concat
local diff = require'ds.diff'

local dt = diff._forTest

local function B(b) return {-1, b} end

test('skip', function()
  assertEq({3, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 1,3)})
  assertEq({2, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 2,3)})
  assertEq({1, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 3,3)})
  assertEq({4, 4}, {dt.skipEqLinesTop({1,1,1}, {1,1,1}, 1,3, 1,3)})

  assertEq({3, 3}, {dt.skipEqLinesBot({1,1,1}, {1,1,2}, 1,3, 1,3)})
  assertEq({1, 0}, {dt.skipEqLinesBot({1,1,1}, {1,1,2}, 1,3, 1,2)})
end)

test('findStack', function()
  local mb     = {3, 5, 12, 20, 30, 50, 60, 70, 90}
  local stacks = {1, 2, 3,  4,  5,  6,  7,  8,  9}
  assertEq(0, dt.findLeftStack(stacks, mb, 2))
  assertEq(1, dt.findLeftStack(stacks, mb, 4))
  assertEq(3, dt.findLeftStack(stacks, mb, 15))
  assertEq(7, dt.findLeftStack(stacks, mb, 69))
end)

local function uniqueMatches(aLines, bLines, a, a2, b, b2)
  if not a then a, a2, b, b2 = 1, #aLines, 1, #bLines end
  return dt.uniqueMatches(aLines, bLines, a, a2, b, b2)
end


local EXPECT = '\n'..[[
   +    1|slits
   +    2|gil
   1    3|david
   2    4|electric
   3    -|gil
   4    -|slits
   5    5|faust
   6    6|sonics
   7    7|sonics
]]
test('example', function()
  --                          1     2        3     4        5     6      7
  local linesA = ds.splitList'david electric gil   slits    faust sonics sonics'
  local linesB = ds.splitList'slits gil      david electric faust sonics sonics'

  local matches = uniqueMatches(linesA, linesB)
  assertEq(dt._BC{
    b={1, 2, 3, 4, 5},
    c={3, 4, 2, 1, 5}}, matches)

  local lis = dt.patienceLIS(matches)
  assertEq({{5, 5}, {2, 4}, {1, 3}}, lis)

  local res = diff(linesA, linesB)
  assertEq(EXPECT, '\n'..Iter:of(res):mapV(tostring):concat'\n'..'\n')

  local chngs = toChanges(res)
  assertEq({
    Change{rem=0, add={'slits', 'gil'}},
    Keep{num=2},
    Change{rem=2, add=nil},
    Keep{num=3},
  }, chngs)
end)

local EXPECT = '\n'..[[
   +    1|X
   1    -|b
   2    2|c
   3    3|d
   +    4|X
   4    -|e
]]
T.test('complex', function()
  local linesA = ds.splitList'b c d e'
  local linesB = ds.splitList'X c d X'

  local matches = uniqueMatches(linesA, linesB)
  assertEq(dt._BC{b={2, 3}, c={2, 3}}, matches)

  local lis = dt.patienceLIS(matches)
  assertEq({{3,3}, {2,2}}, lis)

  local res = diff(linesA, linesB)
  assertEq(EXPECT, '\n'..Iter:of(res):mapV(tostring):concat'\n'..'\n')

  local chngs = toChanges(res)
  assertEq({
    Change{rem=1, add={'X'}},
    Keep{num=2},
    Change{rem=1, add={'X'}},
  }, chngs)
end)

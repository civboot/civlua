
local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local test, assertEq; local T = pkg.auto'civtest'
local Keep, Change, toChanges; pkg.auto'vcds'
local add, concat = table.insert, table.concat
local M = pkg'patience'

local function B(b) return {-1, b} end

test('findStack', function()
  local stacks = {
    B(3),  B(5),  B(12),
    B(20), B(30), B(50),
    B(60), B(70), B(80),
  }
  assertEq(0, M.findLeftStack(stacks, 2))
  assertEq(1, M.findLeftStack(stacks, 4))
  assertEq(3, M.findLeftStack(stacks, 15))
  assertEq(7, M.findLeftStack(stacks, 69))
end)

local function uniqueMatches(aLines, bLines, a, a2, b, b2)
  if not a then a, a2, b, b2 = 1, #aLines, 1, #bLines end
  return M.uniqueMatches(aLines, bLines, a, a2, b, b2)
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
  assertEq({{1, 3}, {2, 4}, {3, 2}, {4, 1}, {5, 5}}, matches)

  local lis = M.patienceLIS(matches)
  assertEq({{5, 5}, {2, 4}, {1, 3}}, lis)

  local diff = M.diff(linesA, linesB)
  assertEq(EXPECT, '\n'..ds.concatToStrs(diff, '\n')..'\n')

  local chngs = toChanges(diff)
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
  assertEq({{2,2}, {3,3}}, matches)

  local lis = M.patienceLIS(matches)
  assertEq({{3,3}, {2,2}}, lis)

  local diff = M.diff(linesA, linesB)
  T.assertEq(EXPECT, '\n'..ds.concatToStrs(diff, '\n')..'\n')

  local chngs = toChanges(diff)
  assertEq({
    Change{rem=1, add={'X'}},
    Keep{num=2},
    Change{rem=1, add={'X'}},
  }, chngs)
end)

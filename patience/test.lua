
local mty = require'metaty'
local ds = require'ds'
local T = require'civtest'
local M = require'patience'

local add = table.insert

local function mockCounts(indexes)
  local out = {}
  for e, i in ipairs(indexes) do out[e] = M.Count(i) end
  return out
end

local function stackIs(stacks)
  local out = {}
  for _, s in ipairs(stacks) do
    local o = {}
    for _, c in ipairs(s) do add(o, c.i) end
    add(out, o)
  end
  return out
end

T.test('patience stacks', function()
  local counts = mockCounts{5, 3, 1, 8, 2, 4, 5}
  local expected = {
    {5, 3, 1},
    {8, 2},
    {4},
    {5},
  }
  local stacks = M.patienceStacks(counts)
  local result = stackIs(stacks)
  T.assertEq(expected, result)

  expected = {1, 2, 4, 5}
  result = M.patienceLIS(stacks)
  T.assertEq(expected, result)
end)

T.test('getEqLines', function()
  local linesA = ds.splitWs'this is incorrect and so is this'
  local linesB = ds.splitWs'this is good and correct and so is this'
  local a, a2, b, b2 = 0, #linesA, 0, #linesB
  T.assertEq({7, 9}, {a2, b2})
  a, b = M.skipEqLinesTop(linesA, linesB, a, a2, b, b2)
  T.assertEq(3, a)
  T.assertEq(3, b)

  a2, b2 = M.skipEqLinesBot(linesA, linesB, a, a2, b, b2)
  T.assertEq(4, a2); T.assertEq(6, b2)
end)

T.test('patienceDiff', function()
  local linesA = ds.splitWs'this is incorrect and so is this'
  local linesB = ds.splitWs'this is good and correct and so is this'
  -- local expected = {
  --     {' ', 'this'}, {' ', 'is'},
  --     {'+', 'good'}, {'+', 'and'}, {'+', 'correct'},
  --     {'-', 'incorrect'},
  --     {' ', 'and'}, {' ', 'so'}, {' ', 'is'}, {' ', 'this'},
  -- }
  local expected = [[
 1       1       | this
 2       2       | is
+        3       | good
+        4       | and
+        5       | correct
-3               | incorrect
 4       6       | and
 5       7       | so
 6       8       | is
 7       9       | this]]
  local result = ds.concatToStrs(M.diff(linesA, linesB), '\n')
  T.assertEq(expected, result)
end)

-- TODO: DEFINITELY not correct
T.test('complex', function()
  local linesA = ds.splitWs'b c d e'
  local linesB = ds.splitWs'X c d X'
  local expected = [[
+        1       | X
-1               | b
 2       2       | c
 3       3       | d
 4       4       | X]]
  local result = ds.concatToStrs(M.diff(linesA, linesB), '\n')
  T.assertEq(expected, result)
end)

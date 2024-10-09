local mty = require'metaty'
local ds = require'ds'
local Iter = require'ds.Iter'
local fmt = require'fmt'
local lines = require'lines'
local T = require'civtest'.Test
local Keep, Change, toChanges; ds.auto'vcds'
local add, concat = table.insert, table.concat
local diff = require'ds.diff'

local dt = diff._toTest
local unpack = table.unpack

local function B(b) return {-1, b} end

T.skip = function()
  T.eq({3, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 1,3)})
  T.eq({2, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 2,3)})
  T.eq({1, 3}, {dt.skipEqLinesTop({1,1,1}, {1,1,2}, 1,3, 3,3)})
  T.eq({4, 4}, {dt.skipEqLinesTop({1,1,1}, {1,1,1}, 1,3, 1,3)})

  T.eq({3, 3}, {dt.skipEqLinesBot({1,1,1}, {1,1,2}, 1,3, 1,3)})
  T.eq({1, 0}, {dt.skipEqLinesBot({1,1,1}, {1,1,2}, 1,3, 1,2)})
end

T.findStack = function()
  local mb     = {3, 5, 12, 20, 30, 50, 60, 70, 90}
  local stacks = {1, 2, 3,  4,  5,  6,  7,  8,  9}
  T.eq(0, dt.findLeftStack(stacks, mb, 2))
  T.eq(1, dt.findLeftStack(stacks, mb, 4))
  T.eq(3, dt.findLeftStack(stacks, mb, 15))
  T.eq(7, dt.findLeftStack(stacks, mb, 69))
end

local function uniqueMatches(aLines, bLines, a, a2, b, b2)
  if not a then a, a2, b, b2 = 1, #aLines, 1, #bLines end
  return dt.uniqueMatches(aLines, bLines, a, a2, b, b2)
end

T.example = function()
  --                          1     2   3        4     5      6     6      7
  local linesA = ds.splitList'david a   electric gil slits    faust sonics sonics'
  local linesB = ds.splitList'slits gil david    a   electric faust sonics sonics'

  local res = diff(linesA, linesB)
  fmt.print('!! Formatted'); fmt.print(res)

  local matches = {uniqueMatches(linesA, linesB)}
  T.eq({
    {1, 2, 3, 4, 5, 6},
    {3, 4, 5, 2, 1, 6}}, matches)

  T.eq({{6, 3, 2, 1},
            {6, 5, 4, 3}},
           {dt.patienceLIS(unpack(matches))})

  T.eq({nil, 3,   nil, 3  }, res.noc)
  T.eq({nil, nil, 2  , nil}, res.rem)
  T.eq({2,   nil, nil, nil}, res.add)

  T.eq(
"          1 slits\
          2 gil\
    1     3 david\
    3     5 electric\
    4       gil\
    5       slits\
    6     6 faust\
    8     8 sonics\
", fmt(res))
end

T.complex = function()
  local linesA = ds.splitList'b c d e'
  local linesB = ds.splitList'X c d X'

  local matches = {uniqueMatches(linesA, linesB)}
  T.eq({{2, 3}, {2, 3}}, matches)

  local lis = {dt.patienceLIS(unpack(matches))}
  T.eq({{3, 2}, {3, 2}}, lis)

  local res = diff(linesA, linesB)
  T.eq({1,   nil, 1  }, res.rem)
  T.eq({1,   nil, 1  }, res.add)
  T.eq({nil, 2  , nil}, res.noc)
end

local function assertDiff(expect, a, b)
  local res = diff(lines(a), lines(b))
  T.eq(expect, fmt(res))
end

T.smallDiffs = function()
  assertDiff(
"          1 peasy\
    1     2 easy\
", "easy", "peasy\neasy")
end


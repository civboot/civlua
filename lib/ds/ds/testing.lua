-- testing helpers for ds related data structures
local M = mod and mod'ds.testing' or {}

local T = require'civtest'
local assertEq = T.assertEq
local ds, lines = require'ds', require'ds.lines'
M.DATA = {}

-- test round-trip offset
local function offsetRound(t, l, c, off, expect, expectOff)
  local l2, c2 = lines.offset(t, off, l, c)
  T.assertEq(expect, {l2, c2})
  local res = lines.offsetOf(t, l, c, l2, c2)
  T.assertEq(expectOff or off, res)
end
M.DATA.offset = '12345\n6789\n'
M.testOffset = function(t)
  local l, c
  offsetRound(t, 1, 2, 0,   {1, 2})
  offsetRound(t, 1, 2, 1,   {1, 3})
  -- here
  offsetRound(t, 1, 1, 3,   {1, 4})
  offsetRound(t, 1, 1, 4,   {1, 5}) -- '5'
  offsetRound(t, 1, 1, 5,   {1, 6}) -- '\n'
  offsetRound(t, 1, 1, 6,   {2, 1}) -- '6'
  offsetRound(t, 1, 1, 9,   {2, 4}) -- '9'
  offsetRound(t, 1, 1, 10,  {2, 5}) -- '\n'
  offsetRound(t, 1, 1, 11,  {3, 1}) -- ''
  offsetRound(t, 1, 1, 12,  {3, 1}, 11) -- EOF

  offsetRound(t, 1, 5, -3,  {1, 2}) -- '2'
  offsetRound(t, 1, 5, -4,  {1, 1}) -- '1'
  offsetRound(t, 1, 5, -5,  {1, 1}, -4) -- '1'

  offsetRound(t, 3, 1, -1,  {2, 5}) -- '\n'
  offsetRound(t, 3, 1, -2,  {2, 4}) -- '9'
  offsetRound(t, 3, 1, -3,  {2, 3}) -- '8'
  offsetRound(t, 3, 1, -4,  {2, 2}) -- '7'
  offsetRound(t, 3, 1, -5,  {2, 1}) -- '6'
  offsetRound(t, 3, 1, -6,  {1, 6}) -- '\n'
  offsetRound(t, 3, 1, -11, {1, 1}) -- '\n'
  offsetRound(t, 3, 1, -12, {1, 1}, -11) -- BOF


  -- Those are all "normal", let's do some OOB stuff
  offsetRound(t, 1, 6 , 1, {2, 1})
  offsetRound(t, 1, 10, 1, {2, 1}) -- note (1, 6) is EOL
end

-- Test lines.remove on object. new must accept either a string or table of
-- lines to create a new object (does NOT need to be copied)
-- called for various data structures which implement lines
M.testLinesRemove = function(new)
  local t = new''
  lines.inset(t, 'foo bar', 1, 0)
  assertEq({'o b'}, lines.remove(t, 1, 3, 1, 5))
  assertEq(new{'foar'}, t)

  lines.inset(t, 'ab\n123', 1, 4)
  assertEq(new{'foaab', '123r'}, t)
  assertEq({'aab', '12'}, lines.remove(t, 1, 3, 2, 2))
  assertEq(new{'fo', '3r'}, t)

  t = new'a\nb'
  assertEq({''}, lines.remove(t, 1, 2, 2, 0)) -- remove newline
  assertEq(new{'ab'}, t)
  assertEq({'ab', ''}, lines.remove(t, 1, 1, 2, 1))
  assertEq(new{''}, t)

  t = new'a\nb'
  assertEq({'', ''}, lines.remove(t, 1, 2, 1, 2)) -- alternate remove newline
  assertEq(new{'ab'}, t)

  t = new'ab\nc'
  assertEq({'b', 'c'}, lines.remove(t, 1, 2, 2, 1))
  assertEq(new{'a', ''}, t)

  t = new'ab\nc'
  assertEq({'b', 'c'}, lines.remove(t, 1, 2, 2, 2))
  assertEq(new{'a'}, t)

  t = new'ab\nc\n\nd'
  assertEq({'c', ''}, lines.remove(t, 2, 3))
  assertEq(new{'ab', 'd'}, t)

  t = new'ab\nc'

  assertEq({'c'}, lines.remove(t, 2, 1, 2, 1)) -- remove c
  assertEq(new{'ab', ''}, t)
  assertEq({''}, lines.remove(t, 1, 3, 2, 0)) -- remove \n (lineskip)
  assertEq(new{'ab'}, t)

  t = new'ab\nc'
  assertEq({'', ''}, lines.remove(t, 1, 3, 1, 3)) -- remove \n (single)
  assertEq(new{'abc'}, t)

  t = new'ab\nc\nde\n'
  assertEq({'', ''}, lines.remove(t, 1, 3, 1, 3)) -- remove \n (single)
  assertEq(new{'abc', 'de', ''}, t)
end

return M

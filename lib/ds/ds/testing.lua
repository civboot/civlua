-- testing helpers for ds related data structures
local M = mod and mod'ds.testing' or {}

local T = require'civtest'
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

return M

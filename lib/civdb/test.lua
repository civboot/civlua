
local T = require'civtest'.Test
local M = require'civdb'
local S = require'civdb.sys'

local char = string.char

T.small = function()
  local str = "hello"
  local enc = S.encodeSmall(str)
  T.binEq(char(0x40 | #str)..str, enc)
  T.binEq(str, S.decodeSmall(enc))

  -- FIXME: need to test integers and booleans too
  local t = {'1', '2', key='value'}
  enc = S.encodeSmall(t)
  T.eq(t, S.decodeSmall(enc))
end

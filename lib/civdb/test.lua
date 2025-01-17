
local T = require'civtest'.Test
local M = require'civdb'
local S = require'civdb.sys'

local char = string.char

T.small = function()
  local str = "hello"
  local enc = S.encode(str)
  T.binEq(char(0x60 | #str)..str, enc)
  T.binEq(str, S.decode(enc))

  -- FIXME: need to test integers and booleans too
  local t = {'11', '22', key='value'}
  enc = S.encode(t)
  T.eq(t, S.decode(enc))

  t[3] = 77
  T.eq(t, S.decode(S.encode(t)))
end

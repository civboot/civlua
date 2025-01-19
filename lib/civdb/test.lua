
local T = require'civtest'.Test
local M = require'civdb'
local S = require'civdb.sys'
local ds = require'ds'

local char = string.char

local RF, IDX = '.out/rowfile.raw', '.out/rowfile.idx'

T.small = function()
  local str = "hello"
  local enc = S.encode(str)
  T.binEq(char(0x60 | #str)..str, enc)
  T.binEq(str, S.decode(enc))

  local t = {'11', '22', key='value'}
  enc = S.encode(t)
  T.eq(t, S.decode(enc))
  t[3] = 77; T.eq(t, S.decode(S.encode(t)))

  local tp = require'ds.testing_pod'
  tp.testAll(S.encode, function(enc)
    local d, len = S.decode(enc)
    T.eq(#enc, len) -- decoded full length
    return d
  end)
end

T.RowFile = function()
  local RowFile = require'civdb.RowFile'
  local rf = RowFile(RF, 'w+')
  local f = rf.f

  -- write and read first row manually
  assert(M.startrow(f, 5))
  assert(f:seek('set', 0)); assert('\5' == f:read())
  assert(f:write'hello', 'what');
  assert(0 == f:seek('set', 0))
  T.eq('\05', f:read(1)); T.eq('hello', f:read(5))
  rf.idx[1] = 0; T.eq(0, rf.idx[1])
  T.eq('hello', rf[1])

  rf[2] = 'my name\0is';
    T.eq('my name\0is', rf[2]);
    T.eq('hello', rf[1])
  rf[3] = 'Rett'; T.eq({'hello', 'my name\0is', 'Rett'}, ds.icopy(rf))
end

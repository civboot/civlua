
local T = require'civtest'.Test
local M = require'civdb'
local S = require'civdb.sys'
local ds = require'ds'
local CivDB = require'civdb.CivDB'

local char = string.char

local DBF, IDX = '.out/file.civdb', '.out/rowfile.idx'

T.small = function()
  local str = "hello"
  local enc = M.encode(str)
  T.binEq(char(0x60 | #str)..str, enc)
  T.binEq(str, M.decode(enc))

  local t = {'11', '22', key='value'}
  enc = M.encode(t)
  T.eq(t, M.decode(enc))
  t[3] = 77; T.eq(t, M.decode(M.encode(t)))

  local tp = require'ds.testing_pod'
  tp.testAll(M.encode, function(enc)
    local d, len = M.decode(enc)
    T.eq(#enc, len) -- decoded full length
    return d
  end)
end

T.CivDB = function()
  local db = CivDB(DBF, 'w+'); db.cache = ds.Forget{}
  T.eq(1, db:createRaw'test1')
  db.f:seek('set', 0)
  --              elen op str5
  T.binEq('civdb\0\x07\xE2\x65test1', db.f:read())
  T.eq(6, db.idx[1])
  T.binEq('test1', db:readRaw(1))

  T.eq(2, db:createRaw(22))
  T.binEq('test1', db:readRaw(1))
  T.eq(22,         db:readRaw(2))
  T.eq(nil,        db:readRaw(3))
  db:close()

  db = CivDB(DBF, 'r+'); db.cache = ds.Forget{}
  T.eq('test1', db:readRaw(1))
end

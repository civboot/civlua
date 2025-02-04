
local T = require'civtest'.Test
local M = require'civdb'
local ds = require'ds'

local char = string.char

local DBF, IDX = '.out/file.civdb', '.out/rowfile.idx'

T.dbRaw = function()
  local db = M.DB:new{path=DBF}; db.cache = ds.Forget{}
  -- T.eq(1, db:createRaw'test1')
  -- db.f:seek('set', 0)
  -- --              elen op str5
  -- T.binEq('civdb\0\x07\xE2\x65test1', db.f:read())
  -- T.eq(6, db.idx[1])
  -- T.binEq('test1', db:readRaw(1))

  -- T.eq(2, db:createRaw(22))
  -- T.binEq('test1', db:readRaw(1))
  -- T.eq(22,         db:readRaw(2))
  -- T.eq(nil,        db:readRaw(3))
  -- db:close()

  -- local f = assert(io.open(DBF, 'r'))
  -- T.binEq('civdb\0\x07\xE2\x65test1', f:read(14))
  -- f:close()

  -- -- reload
  -- local db = M.DB{path=DBF, mode='r+'}; db.cache = ds.Forget{}
  -- T.eq('test1', db:readRaw(1))
  -- T.eq(22,      db:readRaw(2))
  -- T.eq(nil,     db:readRaw(3))
  -- T.eq(3,       db:createRaw{33})
  -- T.eq({33},    db:readRaw(3))

  -- db:updateRaw(2, 23)
  -- T.eq('test1', db:readRaw(1))
  -- T.eq(23,      db:readRaw(2))
  -- T.eq({33},    db:readRaw(3))
  -- db:delete(1); T.eq(nil, db:readRaw(1))
  -- db:close()

  -- -- reload
  -- local db = M.DB{path=DBF, mode='r+'}; db.cache = ds.Forget{}
  -- T.eq(nil,  db:readRaw(1))
  -- T.eq(23,   db:readRaw(2))
  -- T.eq({33}, db:readRaw(3))
end

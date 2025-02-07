
local T = require'civtest'.Test
local M = require'civdb'
local ds = require'ds'
local pod = require'pod'

local char = string.char

local DBF, IDX = '.out/file.civdb', '.out/rowfile.idx'

T.dbRaw = function()
  local db = assert(M.DB:new{path=DBF, schema=pod.builtin})
  db:nocache()
  T.eq(0, #db); db[1] = 'test1'
  db.f:seek('set', 0)
  T.binEq('test1', db[1])
  T.eq(db.path, DBF..'/db')
  T.eq({schema='pod.builtin'}, db._meta)
  T.eq({schema='pod.builtin'}, pod.load(DBF..'/db.meta'))

  T.eq(1, #db); db[2] = 22
  T.eq({'test1', 22}, ds.icopy(db)); T.eq(nil, db[3])
  db:close()

  -- reload
  local db = M.DB:load{path=DBF}; db:nocache()
  T.eq(pod.builtin, db._schema)
  T.eq({'test1', 22}, ds.icopy(db)); T.eq(nil, db[3])
  db[3] = 33
  T.eq({'test1', 22, 33}, ds.icopy(db)); T.eq(nil, db[4])

  db[2] = 23
  T.eq({'test1', 23, 33}, ds.icopy(db)); T.eq(nil, db[4])

  db[1] = nil
  T.eq({nil    , 23, 33}, ds.icopy(db)); T.eq(nil, db[4])
  db:close()

  local db = M.DB:load{path=DBF}; db:nocache()
  T.eq({nil    , 23, 33}, ds.icopy(db)); T.eq(nil, db[4])
  db:close()
end

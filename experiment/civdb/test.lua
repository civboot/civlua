
local mty = require'metaty'
local T = require'civtest'.Test
local M = require'civdb'
local ds = require'ds'
local It = require'ds.Iter'
local pod = require'pod'

local char = string.char

local DBF, IDX = '.out/file.civdb', '.out/rowfile.idx'

-- test module
local Tm = mod'civdb.Tm'
Tm.V = pod(mty'V' {
  'i [int] #1: a int field',
  's [str] #2: a string field',
})
local V = Tm.V

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

-- test query using non-indexed fields
T.queryScan = function()
  local db = assert(M.DB:new{path=DBF, schema=V})
  local rows = {V{i=11}, V{i=22}, V{i=33, s='third'}, V{i=-1}, V{s='last'}}
  ds.extend(db, ds.deepcopy(rows))
  It:ofList(rows):assertEq(It:ofList(db))

  It:ofUnpacked{ {2, V{i=22}}, }
    :assertEq(It{db:query{key='i', 22}})

  It:ofUnpacked{ {5, V{s='last'}}, }
    :assertEq(It{db:query{key='i', nil}})

  It:ofUnpacked{ {1, V{i=11}}, {2, V{i=22}}, {4, V{i=-1}}, }
    :assertEq(It{db:query{key='s', nil}})
end

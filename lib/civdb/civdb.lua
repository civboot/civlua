local G = G or _G
--- civdb: minimalistic CRUD database
---
--- This module exports the encode/decode functions which
--- can be used for encoding and decoding plain-old-data.
local M = G.mod and mod'civdb' or setmetatable({}, {})

local mty = require'metaty'

local pkg = require'pkglib'
local ds = require'ds'
local pth = require'ds.path'
local pod = require'pod'
local LFile = require'lines.File'
local U3File = require'lines.U3File'
local fmt = require'fmt'
local fbin = require'fmt.binary'
local ix = require'civix'

local trace = require'ds.log'.trace
local byte = string.byte
local mtype = math.type
local construct = mty.construct
local index, newindex = mty.index, mty.newindex
local ty = mty.ty
local encv = require'pod.native'.enci
local ser, deser = pod.ser, pod.deser
local WeakV = ds.WeakV

local fileInit = getmetatable(LFile).__call

M.DB = mty'DB' {
  'schema [pod.Podder]: the type to deserialize each row',
  'meta [table]: table of metadata',
  'path [string]', 'mode [string]',
  'f [File]',
  '_rows [lines.U3File]: row -> pos',
  'cache [ds.WeakV]: cache of rows',
  '_eofpos [nil|int]: nil or pos at eof',
}
getmetatable(M.DB).__call = function(T, t)
  error'use :new{} or :load{}'
end
local DB = M.DB
DB.MAGIC = 'civdb\0'
DB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

-- subtract 1: rows[1] is metadata
DB.__len = function(db) return #db._rows - 1 end

---------------------
--- Op Type: this specifies what the entry is doing
M.Op = mty'Op' {
  'kind [civdb.Op.Kind]',
  'row  [int]: the row index being modified',
  'other [table]',
}

M.Op.Kind = mty.enum'Op.Kind' {
  CREATE = 1, DELETE = 2, UPDATE = 3, OTHER  = 4,
}
local Op, OpKind = M.Op, M.Op.Kind

local CREATE_OP = assert(ser(true))
local updateOp = function(row)  return ser( row) end
local deleteOp = function(row)  return ser(-row) end
local otherOp  = ser

--- Op:decode(val) - decode the operation from lua value.
Op.decode = function(T, v) --> Op
  if v == true then return T{kind=OpKind.CREATE} end
  if type(v) == 'table' then return T{kind=OpKind.OTHER, other=v} end
  assert(mtype(v) == 'integer', 'invalid op')
  if v >= 0    then return T{kind=OpKind.UPDATE, row= v}
               else return T{kind=OpKind.DELETE, row=-v} end
end

----------------------------
-- Entry functions: how data is written/read from the file

--- read the raw bytes of the next counted entry from a file
local readEntryRaw = function(f) --> (string?, lensz|error)
  local len, sh, s = 0, 0
  while true do
    s = f:read(1); if not s then return nil end
    local b = byte(s); len = ((0x7F & b) << sh) | len
    if (0x80 & b) ~= 0 then sh = sh + 7 else break end
  end
  trace('readEntry len=%i', len)
  s = f:read(len); if not s then return nil, 'readEntry len' end
  if not s or len ~= #s then
    return nil, sfmt('did not read full len: %i ~= %i', len, #s)
  end
  return s, (sh + 7) // 7
end

--- read the Op, oplen and (whole) rawdat of of the next entry from a file
--- if the rawdat are decoded they must be offset by oplen+1
local readEntryOp = function(f) -- op, oplen, rawdat, lensz
  local dat, lensz = readEntryRaw(f)
  print('!! readTx lensz:', lensz)
  if not dat then return nil, nil, lensz end
  local op, oplen = deser(dat)
  trace('readTx: op=%q vlen=%i', op, #dat - oplen)
  return Op:decode(op), oplen, dat, lensz
end

--- write the raw operation and raw data, return bytes written
--- Note: the rawop are created with the *Op() functions.
local writeEntry = function(f, pos, rawop, dat) --> writelen
  local f, pos, len = db.f, db._eofpos, #rawop + #dat
  assert(pos); assert(pos == f:seek('set', pos))

  local elenstr = encv(len)
  assert(f:write(elenstr))
  assert(f:write(op)); assert(f:write(dat))
  trace('pushvalue pos=%i enclen=%i len=%i', pos, #elenstr, len)
  return #elenstr + len
end


-----------------------
-- READ

local opDeser = function(db, oplen, rawdat)
  return deser(rawdat, db.schema, oplen + 1)
end
local opRead = Op.Kind:matcher{
  CREATE = opDeser, UPDATE = opDeser, DELETE = ds.noop,
  OTHER = function() error'unreachable' end,
}

--- Read the row, returning its value
--- Note: does not attempt to convert to the schema type.
DB.readRaw = function(db, row) --> Op, oplen, rawdat
  local pos = db._rows[row]
  trace('readRaw row=%i from pos=%s', row, pos)
  if not pos or pos == 0 then return end
  assert(pos == db.f:seek('set', pos))
  return readEntryOp(db.f)
end

DB.__index = function(db, row)
  if type(row) == 'string' then
    local mt = getmt(db)
    return rawget(mt, row) or index(db, i)
  end
  trace('__index row=%i', row)
  assert(row >= 1, 'row must be >= 1')
  row = row + 1  -- rows[1] is metadata
  local op, oplen, rawdat = db:readRaw(row, db.schema)
  return opRead[op.kind](db, oplen, rawdat)
end


-----------------------
-- CREATE / UPDATE / DELETE

DB.__newindex = function(db, row, v)
  if type(i) == 'string' then return newindex(lf, i, v) end
  local vty; if v ~= nil then vty = ty(v)
    if not rawequal(vty, db.schema) then error(fmt(
      'schema ty %q ~= val ty %q', db.schema, vty
    ))end
  end
  assert(row >= 1, 'row must be >= 1')
  row = row + 1  -- _rows[1] is metadata
  local len = #db._rows
  local f, rows, pos, epos = db.f, db._rows, db._eofpos, nil
  if row > len then
    assert(row == len + 1, "can only set from [1,len+1]")
    epos = pos + writeEntry(f, pos, createOp(), ser(v, vty))
  elseif v == nil then
    epos = pos + writeEntry(f, pos, deleteOp(row), '')
  else
    epos = pos + writeEntry(f, pos, updateOp(row), ser(v, vty))
  end
  rows[row], db._eofpos = pos, epos
end

-----------------------
-- Creating / Loading Database

local getIdxPath = function(path, rowsPath)
  return rowsPath or pth.concat{DB.IDX_DIR, path}
end

--- Do basic argument checking and initializaiton
local dbInit = function(T, t) --> db, rowsPath
  local path = assert(t.path, 'must provide path')
  local rowsPath = getIdxPath(path, ds.popk(t, 'rowsPath'))
  local t = construct(T, t)
  local ok, err = pod.isPodder(assert(t.schema, 'must set schema'))
  if not ok then fmt.errorf('schema %s is not Podder: %s', t.schema, err) end
  return t, rowsPath
end


DB.new = function(T, t)
  trace('civdb.DB new %q', t)
  local t, rowsPath = dbInit(T, t)
  local f, err, rows
  f, err = io.open(db.path, 'w+');  if not f   then return nil, err end
  rows, err = U3File(rowsPath, 'w+'); if not idx then return nil, err end
  t.meta = t.meta or {}
  t.meta.schema     = G.PKG_NAMES[t.schema]
  t.meta.createdSec = t.meta.created or ix.epoch().s

  assert(f:write(T.MAGIC))
  local elen = writeEntry(f, #T.MAGIC, otherOp{meta=t.meta}, '')
  rows[1] = #T.MAGIC
  t.f, t._rows, t.cache = f, rows, ds.WeakV{}
  t._eofpos = #T.MAGIC + elen
  return t
end

local opRow = function(_rows, row, pos) rows[row] = pos end
local opReindex = Op.Kind:matcher{
  CREATE = function(_rows, _,   pos) rows[#_rows+1]   = pos end,
  UPDATE = function(_rows, row, pos) rows[row+1]    = pos end,
  DELETE = function(_rows, row, _)   rows[row+1]    = 0   end,
  OTHER  = function(_rows, _, pos)   rows[1]        = pos end,
}

local finishRows = function(db, rows)
  local mpos = rows[1]; if not mpos or mpos == 0 then
    return nil, 'no metadata'
  end; assert(mpos == f:seek('set', mpos))
  local op = readEntryOp(f)
  local meta = G.op.other.meta
  local schema = assert(pkg.getpath(meta.schema), meta.schema)
  if db.schema and not rawequal(db.schema, schema) then fmt.errorf(
    'loaded schema %q not equal to set schema %q', schema, db.schema
  )end
  assert(pod.isPodder(schema)); db.schema = schema
  db._rows, db.meta = rows, meta
end

DB.reindex = function(db, rowsPath)
  rowsPath = getIdxpath(db.path, rowsPath)
  local rows, err = U3File(rowsPath, 'w+')
  if not rows then return err end
  local f, pos = db.f, #DB.MAGIC; local len = f:seek'end'
  trace('DB reindex pos=%i len=%s', row, pos, len)
  f:seek'set'; assert(DB.MAGIC == f:read(#DB.MAGIC))
  while pos < len do
    local op, _, rawdat, lensz = readEntryOp(f)
    if not op then break end -- incomplete entry, treat as EOF
    opReindex[op.kind](_rows, op.row, pos)
    pos = pos + lensz + #rawdat
  end
  finishRows(db, rows)
  db._eofpos = pos
  return db
end

DB.tryLoadIdx = function(db, rowsPath)
  rowsPath = getIdxpath(db.f, rowsPath)
  if not ix.exists(rowsPath)              then return end
  if not ix.modifiedEq(db.path, rowsPath) then return end
  rows, err = U3File(rowsPath, 'r+'); if not rows then return end
  finishRows(db, rows)
  return true
end

DB.load = function(T, t)
  trace('civdb.DB load %q', t)
  local t, rowsPath = dbInit(T, t)
  if not ix.exists(t.path) then error('path not found: '..t.path) end
  local err;
  t.f, err = io.open(t.path, 'a+'); if not t.f then return nil, err end
  t:tryLoadIdx(rowsPath)
  return t
end

DB.needsReindex = function(db) return nil ~= db._rows end

DB.check = function(db) --> ok, err
  if db:needsReindex() then return false, 'needs :reindex()' end
end

DB.flush = function(db)
  local ok, err = db.rows:flush(); if not ok then return nil, err end
  ok, err = db.f:flush()           if not ok then return nil, err end
  local fs, err = ix.stat(db.f);   if not fs then return nil, err end
  return ix.setModified(db.rows.f, fs:modified())
end

DB.close = function(db)
  db:flush(); db.rows:close(); db.f:close();
end

return M

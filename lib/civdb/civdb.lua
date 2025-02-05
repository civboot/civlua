local G = G or _G
--- civdb: minimalistic CRUD database
---
--- This module exports the encode/decode functions which
--- can be used for encoding and decoding plain-old-data.
local M = G.mod and mod'civdb' or setmetatable({}, {})

local mty = require'metaty'

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
  'idx [lines.U3File]: row -> pos',
  'cache [ds.WeakV]: cache of rows',
  '_eofpos [nil|int]: nil or pos at eof',
}
getmetatable(M.DB).__call = function(T, t)
  error'use :new{} or :load{}'
end
local DB = M.DB
DB.MAGIC = 'civdb\0'
DB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

-- subtract 1: idx[1] is metadata
DB.__len = function(db) return #db.idx - 1 end

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
local readEntryOp = function(f) -- op, oplen, rawdat
  local dat, lensz = readEntry(f)
  print('!! readTx lensz:', lensz)
  if not dat then return nil, nil, lensz end
  local op, oplen = deser(dat)
  trace('readTx: op=%q vlen=%i', op, #dat - oplen)
  return Op:decode(op), oplen, dat
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
  local pos = db.idx[row]
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
  row = row + 1  -- idx[1] is metadata
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
  row = row + 1  -- idx[1] is metadata
  local len = #db.idx
  local f, idx, pos, epos = db.f, db.idx, db._eofpos, nil
  if row > len then
    assert(row == len + 1, "can only set from [1,len+1]")
    epos = pos + writeEntry(f, pos, createOp(), ser(v, vty))
  elseif v == nil then
    epos = pos + writeEntry(f, pos, deleteOp(row), '')
  else
    epos = pos + writeEntry(f, pos, updateOp(row), ser(v, vty))
  end
  idx[row], db._eofpos = pos, epos
end

-----------------------
-- Creating / Loading Database

--- Do basic argument checking and initializaiton
local dbInit = function(t, path) --> db, idxpath
  local path = assert(t.path, 'must provide path')
  local idxpath = ds.pop(t, 'idxpath') or pth.concat{DB.IDX_DIR, path}
  local t = construct(T, t)
  local ok, err = pod.isPodder(assert(t.schema, 'must set schema'))
  if not ok then fmt.errorf('schema %s is not Podder: %s', t.schema, err) end
  return t, idxpath
end

DB.new = function(T, t)
  trace('civdb.DB new %q', t)
  local t, idxpath = dbInit(t)
  local f, err, idx
  f, err = io.open(db.path, 'w+');  if not f   then return nil, err end
  idx, err = U3File(idxpath, 'w+'); if not idx then return nil, err end
  t.meta = t.meta or {}
  t.meta.schema     = G.PKG_NAMES[t.schema]
  t.meta.createdSec = t.meta.created or ix.epoch().s

  assert(f:write(T.MAGIC))
  local elen = writeEntry(f, #T.MAGIC, otherOp{meta=t.meta}, '')
  idx[1] = #T.MAGIC
  t.f, t.idx, t.cache = f, idx, ds.WeakV{}
  t._eofpos = #T.MAGIC + elen
  return t
end

local tryLoadIdx = function(db, idxpath)
  if not civix.exists(idxpath) then return end
  if not fd.modifiedEq(db.path, idxpath) then return end
  idx, err = U3File(idxpath, 'r+'); if not idx then return end

end

DB.load = function(T, t)
  trace('civdb.DB load %q', t)
  local t, idxpath = dbInit(t)
  local f, err, idx, fstat, xstat
  if not civix.exists(t.path) then error('path not found: '..t.path) end
  t.idx = tryLoadIdx(db, idxpath)

  f, err = io.open(t.path, 'a+'); if not f then return nil, err end

  return t
end

-----------------------
-- JUNK

DB._initnew = function(f) assert(f:write(DB.MAGIC)) end
DB._reindex = function(f, idx, row, pos)
  local magic = DB.MAGIC
  row, pos = row or 1, pos or 0
  local len = f:seek'end'
  trace('DB _reindex row=%i pos=%i len=%s', row, pos, len)
  if len < 6 then
    assert(pos == 0); assert(0 == f:seek'set')
    assert(f:write(magic))
    pos = 6
  elseif pos < 6 then
    assert(pos == 0); assert(0 == f:seek'set')
    assert(f:read(#magic) == magic)
    pos = 6
  else assert(pos == f:seek('set', pos)) end
  trace('      _reindex row=%i pos=%i len=%s', row, pos, len)

  while pos < len do
    local op, val, readSz = readTx(f); assert(op, val);
    trace('reindex op=%q val=%q readSz=%s', op, val, readSz)
    if     op.kind == 'delete' then idx[op.row] = 0
    elseif op.kind == 'update' then idx[op.row] = pos
    elseif op.kind == 'create' then
      idx[row] = pos; row = row + 1
    else error('unknown op: '..fmt(op)) end
    pos = pos + readSz
  end
end

DB.__len = function(db) return #db.idx end

--- Create a new row with value, returning the rownum
--- Note: directly encodes with toPod (ignores schema)
DB.createRaw = function(db, value, vty) --> row
  local idx = db.idx; local row = #idx + 1
  local pos, dat = db:_pushvalue(CREATE_OP, value)
  trace('createRow row=%i pos=%i', row, pos)
  idx[row] = pos;
  db.cache[row] = dat
  return row
end

--- Modify the value of the row with the value
--- Note: directly encodes with toPod (ignores schema)
DB.updateRaw = function(db, row, value)
  local idx = db.idx; assert(row <= #idx)
  local pos, dat = db:_pushvalue(updateOp(row), value)
  idx[row], db.cache[row] = pos, dat
end

--- Delete the row, future reads will return nil
DB.delete = function(db, row)
  local op = deleteOp(row)
  local f, pos = db.f, db._eofpos
  assert(pos == f:seek('set', pos))
  local enclen = assert(startEntry(f, #op))
  assert(f:write(op))
  db._eofpos = pos + enclen + #op
  db.idx[row] = 0; db.cache[row] = nil
end

DB._pushvalue = function(db, op, value, vty) --> pos, dat
  print('!! pushvalue', fbin(op), value)
  local dat = assert(ser(value, vty))
  local f, pos, len = db.f, db._eofpos, #op + #dat
  assert(pos)
  assert(pos == f:seek('set', pos))
  local enclen = assert(startEntry(f, len))
  assert(f:write(op)); assert(f:write(dat))
  trace('pushvalue pos=%i enclen=%i len=%i', pos, enclen, len)
  db._eofpos = pos + enclen + len
  return pos, dat
end

DB.flush = LFile.flush
DB.close = function(db)
  db:flush(); db.idx:close(); db.f:close();
end

return M

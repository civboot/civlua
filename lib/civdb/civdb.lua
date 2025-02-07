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
local encv = require'pod.native'.enci

local getmt = getmetatable
local byte = string.byte
local mtype = math.type
local construct = mty.construct
local index, newindex = mty.index, mty.newindex
local ty = mty.ty
local ser, deser = pod.ser, pod.deser
local WeakV = ds.WeakV

local fileInit = getmetatable(LFile).__call

M.DB = mty'DB' {
  'path [string]', 'datPath [string]', 'metaPath [string]',
  'f [File]', 'mode [string]',
  '_schema [pod.Podder]: the type to deserialize each row',
  '_rows [lines.U3File]: row -> pos',
  'cache [ds.WeakV]: cache of rows',
  '_eofpos [nil|int]: nil or pos at eof',
  '_meta [table]',
}
getmetatable(M.DB).__call = function(T, t)
  error'use :new{} or :load{}'
end
local DB = M.DB
DB.MAGIC = 'civdb\0'
DB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

DB.__len = function(db) return #db._rows end

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
  local len = #rawop + #dat
  assert(pos);
  assert(pos == f:seek('set', pos))
  local elenstr = encv(len)
  assert(f:write(elenstr))
  assert(f:write(rawop)); assert(f:write(dat))
  trace('pushvalue pos=%i enclen=%i len=%i', pos, #elenstr, len)
  return #elenstr + len
end


-----------------------
-- READ

local opDeser = function(db, oplen, rawdat)
  return deser(rawdat, db._schema, oplen + 1)
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
    return rawget(mt, row) or index(mt, row)
  end
  trace('__index row=%i', row)
  assert(row >= 1, 'row must be >= 1')
  local op, oplen, rawdat = db:readRaw(row, db._schema)
  if not op then return end
  return opRead[op.kind](db, oplen, rawdat)
end

-----------------------
-- CREATE / UPDATE / DELETE

DB.__newindex = function(db, row, v)
  if type(row) == 'string' then return newindex(db, row, v) end
  assert(row >= 1, 'row must be >= 1')
  local len = #db._rows
  local f, rows, pos, epos = db.f, db._rows, db._eofpos, nil
  if row > len then
    assert(row == len + 1, "can only set from [1,len+1]")
    epos = pos + writeEntry(f, pos, CREATE_OP, ser(v, db._schema))
  elseif v == nil then
    epos = pos + writeEntry(f, pos, deleteOp(row), '')
  else
    epos = pos + writeEntry(f, pos, updateOp(row), ser(v, db._schema))
  end
  rows[row], db._eofpos = pos, epos
end

-----------------------
-- META

--- [$db:meta()] get's the metadata and [$db:meta(new)] updates it. The
--- schema is overriden with the current schema [$PKG_NAME].
---
--- Note: this updates the metadata inside a [$db] file as well as the
--- [$db.meta] file. Do not modify the result of [$:meta()] directly unless you
--- are immediately passing it back.
DB.meta = function(db, meta)
  if not meta then return db._meta end
  local pos = db._eofpos
  meta.schema = G.PKG_NAMES[db._schema]
  db._eofpos = pos + writeEntry(db.f, pos, otherOp{meta=meta}, '')
  db._meta = meta
end

--- [+ * [$db:schema()] returns the current schema
---    * [$db:schema(newSchema)] sets a new schema]
---
--- ["WARNING: the new schema must be byte-compatible with the old one, else
---   existing data will break on read. You may need to reindex the table after
---   setting a new schema.]
DB.schema = function(db, schema) --> current schema
  if schema then
    local ok, err = pod.isPodder(schema)
    if not ok then fmt.errorf('schema %s is not Podder: %s', schema, err) end
    db._schema = schema; db:meta(db._meta)
  end
  return db._schema
end


-----------------------
-- Creating / Loading Database

--- Do basic argument checking and initializaiton
local dbInit = function(t) --> t
  t.path = (not ix.exists(assert(t.path, 'must provide path'))
            or ix.isDir(t.path)) and pth.concat{t.path, 'db'}
           or t.path
  return t
end


DB.new = function(T, t)
  trace('civdb.DB new %q', t)
  local schema = assert(ds.popk(t, 'schema'), 'must set schema')
  t = dbInit(t); t._meta = ds.popk(t, 'meta') or {}
  t = construct(T, t)
  local f, err, rows
  ix.mkDirs((pth.last(t.path)))
  f,    err = io.open(t.path, 'w+'); if not f then return nil, err end
  rows, err = U3File:create(t.path..'.rows')
  if not rows then return nil, err end
  assert(f:write(T.MAGIC)); t._eofpos = #T.MAGIC
  t.f, t._rows, t.cache = f, rows, ds.WeakV{}
  t:schema(schema)
  return t
end

local opRow = function(_rows, row, pos) rows[row] = pos end
local opReindex = Op.Kind:matcher{
  CREATE = function(rows,  _,   pos) rows[#rows+1] = pos end,
  UPDATE = function(rows, row, pos)  rows[row]     = pos end,
  DELETE = function(rows, row, _)    rows[row]     = 0   end,
  OTHER  = function() error'unreachable' end,
}

local reindex = function(f, path) --> endpos, rows, meta
  local rowsPath = path..'.rows'
  local rows, err = assert(U3File:create(rowsPath))
  local pos = #DB.MAGIC; local len = f:seek'end'
  trace('reindex pos=%i len=%s', pos, len)
  f:seek'set'; assert(DB.MAGIC == f:read(#DB.MAGIC))
  local meta
  while pos < len do
    local op, _, rawdat, lensz = readEntryOp(f)
    if not op then break end -- incomplete entry, treat as EOF
    if op.other then
      if op.other.meta then meta = op.other.meta end
    else
      opReindex[op.kind](rows, op.row, pos)
    end
    pos = pos + lensz + #rawdat
  end
  assert(meta, 'OTHER.meta was never set')
  return pos, rows, meta
end

local tryLoad = function(f, path) --> pos?, rows?, meta?
  local rowsPath, metaPath = path..'.rows', path..'.meta'
  if not ix.exists(rowsPath)              then return end
  if not ix.modifiedEq(f, rowsPath) then return end
  if not ix.modifiedEq(f, metaPath) then return end
  local rows = assert(U3File:load(rowsPath))
  local meta = assert(pod.deser(ds.readPath(metaPath), pod.table))

  print('!! #rows', #rows)
  local pos; if #rows == 0 then pos = #DB.MAGIC
  else                          pos = rows[#rows] end
  f:seek('set', pos);
  local str, lensz = readEntryRaw(f); assert(str, lensz)
  return pos + lensz + #str, rows, meta
end

DB.load = function(T, t)
  trace('civdb.DB load %q', t)
  local t = dbInit(t)
  if not ix.exists(t.path) then error('path not found: '..t.path) end
  local err;
  t.f, err = io.open(t.path, 'a+'); if not t.f then return nil, err end
  local pos, rows, meta = tryLoad(t.f, t.path)
  if not rows then pos, rows, meta = reindex(t.f, t.path) end
  if not rows then error("couldn't reload "..t.path..'.rows') end

  t._schema = PKG_LOOKUP[assert(meta.schema, 'no schema in meta')]
  t._eofpos, t._rows, t._meta = pos, rows, meta
  return construct(T, t)
end

DB.flush = function(db)
  local ok, err = db._rows:flush(); if not ok then return nil, err end
  ok, err = db.f:flush()           if not ok then return nil, err end
  local fs, err = ix.stat(db.f);   if not fs then return nil, err end
  ix.setModified(db._rows.f,       fs:modified())
  ix.setModified(db.path..'.meta', fs:modified())
end

DB.close = function(db)
  db:flush(); db._rows:close(); db.f:close();
end

DB.nocache = function(db) db.cache = ds.Forget{} end

return M

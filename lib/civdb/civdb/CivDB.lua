local mty = require'metaty'
--- a database object backed by a civdb CFile
local CivDB = mty'civdb.CivDB' {
  'f [File]', 'path [string]',
  'idx [lines.U3File]: row -> pos',
  'cache [WeakV]: cache of rows',
  '_row [int] the next row', _row = 1,
  '_eofpos [nil|int]: nil or pos at eof',
}
CivDB.MAGIC = 'civdb\0'

local ds = require'ds'
local pth = require'ds.path'
local LFile = require'lines.File'
local civdb = require'civdb'
local S = require'civdb.sys'

local construct = mty.construct
local mtype = math.type
local fmt = require'fmt'
local fbin = require'fmt.binary'
local byte = string.byte
local trace = require'ds.log'.trace

local encv = S.encv
local encode, decode = civdb.encode, civdb.decode

local fileInit = getmetatable(LFile).__call


----------------------------
-- Utility Functions

--- Start an entry by writing the encoded length.
--- It is the caller's job to actually write the entry data.
local startEntry = function(f, len) --> byteswritten?, err
  len = encv(len); assert(f:write(len))
  return #len
end

--- read the next counted entry from a file, decoding the length with decv.
local readEntry = function(f) --> (string?, lensz|error)
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

local Op = mty'Op' {
  'kind [string]: create, delete or update',
  'row  [int]: the row index being modified',
}

local CREATE_OP = assert(encode(true))
local updateOp = function(row) return encode( row) end
local deleteOp = function(row) return enocde(-row) end

--- Op:decode(val) - decode the operation.
Op.decode = function(T, v)
  if v == true then return T{kind='create'} end
  assert(mtype(v) == 'number', 'invalid op')
  if v >= 0    then return T{kind='update', row= v}
               else return T{kind='delete', row=-v} end
end

--- read a single transaction from the file
local readTx = function(f) --> Op, value, readamt
  local tx, lensz = readEntry(f)
  print('!! readTx lensz:', lensz)
  if not tx then return nil, nil, lensz end
  local op, oplen = decode(tx)
  trace('readTx: op=%q vlen=%i', op, #tx - oplen)
  return Op:decode(op), decode(tx, oplen + 1), lensz + #tx
end

----------------------------
-- CivDB Type

CivDB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

getmetatable(CivDB).__call = function(T, t)
  local mode = t.mode or 'w+'
  local db = assert(fileInit(T, t.path, mode))
  db._eofpos = assert(db.f:seek'end')
  db._row = #db.idx + 1
  return db
end

CivDB._initnew = function(f) assert(f:write(CivDB.MAGIC)) end
CivDB._reindex = function(f, idx, row, pos)
  local magic = CivDB.MAGIC
  row, pos = row or 1, pos or 0
  local len = f:seek'end'
  if len < 6 then
    assert(pos == 0); assert(0 == f:seek'set')
    assert(f:write(magic))
    pos = 6
  elseif pos < 6 then
    assert(pos == 0); assert(0 == f:seek'set')
    assert(f:read(#magic) == magic)
    pos = 6
  else assert(pos == f:seek('set', pos)) end

  while pos < len do
    local op, val, readSz = readTx(f); assert(op, val);
    if     op.kind == 'delete' then idx[op.row] = 0
    elseif op.kind == 'update' then idx[op.row] = pos
    elseif op.kind == 'create' then
      idx[row] = pos; row = row + 1
    else error('unknown op: '..fmt(op)) end
    pos = pos + readSz
  end
end

CivDB.__len = function(db) return #db.idx end

--- Create a new row with value, returning the rownum
--- Note: directly encodes with toPod (ignores schema)
CivDB.createRaw = function(db, value) --> row
  local row = db._row
  local pos, dat = db:_pushvalue(CREATE_OP, value)
  trace('createRow row=%i pos=%i', row, pos)
  db.idx[row] = pos; db._row = row + 1
  db.cache[row] = dat
  return row
end

--- Read the row, returning its value
--- Note: does not attempt to convert to the schema type.
CivDB.readRaw = function(db, row) --> value?
  local pos = db.idx[row]
  trace('readRaw row=%i from pos=%s', row, pos)
  if not pos or pos == 0 then return end
  local f = db.f; assert(pos == f:seek('set', pos))
  local op, val = readTx(f)
  trace('readRaw: row=%i op=%q val=%q', row, op, val)
  return not op and error(val) or val
end

--- Modify the value of the row with the value
--- Note: directly encodes with toPod (ignores schema)
CivDB.updateRaw = function(db, row, value)
  local row = db._row
  local pos, dat = db:_pushvalue(updateOp(row), value)
  db.idx[row] = pos; db._row = row + 1
  db.cache[row] = dat
end

--- Delete the row, future reads will return nil
CivDB.delete = function(db, row)
  local op = deleteOp(row)
  local f, pos = db.f, db._eofpos
  assert(pos == f:seek('set', pos))
  local enclen = assert(startEntry(f, #op))
  assert(f:write(op))
  db._eofpos = pos + enclen + #op
  db.idx[row] = 0; db.cache[row] = nil
end

CivDB._pushvalue = function(db, op, value) --> pos, dat
  print('!! pushvalue', fbin(op), value)
  local dat = assert(encode(value))
  local f, pos, len = db.f, db._eofpos, #op + #dat
  assert(pos)
  assert(pos == f:seek('set', pos))
  local enclen = assert(startEntry(f, len))
  assert(f:write(op)); assert(f:write(dat))
  trace('pushvalue pos=%i enclen=%i len=%i', pos, enclen, len)
  db._eofpos = pos + enclen + len
  return pos, dat
end

CivDB.flush = LFile.flush
CivDB.close = function(db)
  db:flush(); db.idx:close(); db.f:close();
end

return CivDB

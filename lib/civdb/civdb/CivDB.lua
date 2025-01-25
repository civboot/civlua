local mty = require'metaty'
--- a database object backed by a civdb CFile
local CivDB = mty'civdb.CivDB' {
  'f [File]',
  'idx [lines.U3File]: row -> pos',
  'cache [WeakV]: cache of rows',
  '_row [int] the next row', _row = 1,
  '_eofpos [nil|int]: nil or pos at eof',
}
CivDB.MAGIC = 'civdb\0'

local pth = require'ds.path'
local LFile = require'lines.File'
local futils = require'civdb.futils'
local civdb = require'civdb'

local construct = mty.construct
local mtype = math.type
local fmt = require'fmt'

local encode, decode = civdb.encode, civdb.decode
local startEntry, readTx = futils.startEntry, futils.readTx

CivDB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

getmetatable(CivDB).__call = getmetatable(LFile).__call

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
  idx[row] = pos; db._row = row + 1
  db._cache[row] = dat
  return row
end

--- Read the row, returning its value
--- Note: does not attempt to convert to the schema type.
CivDB.readRaw = function(db, row) --> value?
  local pos = db.idx[row]; if not pos or pos == 0 then return end
  local f = db.f; assert(pos == f:seek(pos))
  local op, val = readTx(f)
  if not op then error(val) end
  if val then return (decode(val)) end -- else nil
end

--- Modify the value of the row with the value
--- Note: directly encodes with toPod (ignores schema)
CivDB.updateRaw = function(db, row, value)
  local row = db._row
  local pos, dat = db:_pushvalue(updateOp(row), value)
  idx[row] = pos; db._row = row + 1
  db._cache[row] = dat
end

--- Delete the row, future reads will return nil
CivDB.delete = function(db, row)
  local op = deleteOp(row)
  local f, pos = db.f, db._eofpos
  assert(pos == f:seek(pos))
  local enclen = assert(startEntry(f, #op))
  assert(f:write(op))
  db._eofpos = pos + enclen + #op
  idx[row] = 0; db._cache[row] = nil
end

CivDB._pushvalue = function(db, op, value) --> pos, dat
  local dat = assert(encode(value))
  local f, pos, len = db.f, db._eofpos, #op + #dat
  assert(pos == f:seek(pos))
  local enclen = assert(startEntry(f, len))
  assert(f:write(op)); assert(f:write(dat))
  db._eofpos = pos + enclen + len
  return pos, dat
end

return CivDB

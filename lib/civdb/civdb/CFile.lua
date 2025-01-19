local mty = require'metaty'

--- Indexed file which contains entries encoded by their length
--- followed by their data.
---
--- The length is encoded using continuation bits: the 0x80 bit means next
--- byte has the next 7 more-significant-bits.
local CFile = mty'civdb.CFile' {
  'f   [file]: open file', 'path [string]',
  'idx [lines.U3File]: row index of f',
  'cache [WeakV]: cache of rows',
  '_eofpos [nil|int]: nil or pos at eof',
}

local civdb = require'civdb'
local S = require'civdb.sys'
local ds = require'ds'
local pth = require'ds.path'
local log = require'ds.log'
local lines = require'lines'
local LFile = require'lines.File'
local fd = require'fd'
local ix = require'civix'

local getmt = getmetatable
local index, newindex = mty.index, mty.newindex
local sfmt, byte = string.format, string.byte
local encv, decv = S.encv, S.decv

--- Start a row by encoding the length.
--- It is the caller's job to actually write the row data.
local startrow = function(file, len) --> byteswritten?, err
  len = encv(len); assert(file:write(len), 'write error')
  return #len
end

--- read the next row from a file, decoding the length with decv
--- Return the row and the length of the encv integer encoding.
local readrow = function(file) --> (string?, lensz|error)
  local len, sh, s = 0, 0
  while true do
    s = file:read(1); if not s then return nil end
    local b = byte(s); len = ((0x7F & b) << sh) | len
    if (0x80 & b) ~= 0 then sh = sh + 7 else break end
  end
  s = file:read(len); if not s then return nil, 'read row data' end
  if not s or len ~= #s then
    return nil, sfmt('did not read full len: %i ~= %i', len, #s)
  end
  return s, (sh + 7) // 7
end

CFile._startrow, CFile.readrow = startrow, readrow

CFile.IDX_DIR = pth.concat{pth.home(), '.data/rf'}
getmetatable(CFile).__call    = getmetatable(LFile).__call
CFile.close     = LFile.close
CFile.flush     = LFile.flush
CFile.__len     = LFile.__len
CFile.__reader  = LFile.reader

CFile._reindex = function(f, idx, r, pos)
  r, pos = r or 1, pos or 0
  if f:seek'end' == 0 then return end
  assert(f:seek('set', pos))
  while true do
    idx[r] = pos; r = r + 1
    local row, encsz = readrow(f)
    if not row then assert(not encsz, encsz); break end
    pos = pos + encsz + #row
  end
  return pos
end

getmetatable(CFile).__index  = nil
CFile.__index = function(rf, i)
  if type(i) == 'string' then
    local mt = getmt(rf)
    return rawget(mt, i) or index(mt, i)
  end
  local cache = rf.cache
  local row, rowsz = cache[i]; if row then return row end
  local f, idx = rf.f, rf.idx
  if i > #idx then return end -- line num OOB
  local pos = assert(rf.idx[i])
  print('!! pos', pos)
  rf._eofpos = nil
  assert(pos == assert(f:seek('set', pos)))
  row, rowsz = readrow(f); assert(row, rowsz)
  return row
end

CFile.__newindex = function(rf, i, v)
  if type(i) == 'string' then return newindex(rf, i, v) end
  local f, idx, cache, pos = rf.f, rf.idx, rf.cache, rf._eofpos
  local pos = rf._eofpos or assert(f:seek'end')
  local len = #idx; assert(i == len + 1, 'only append allowed')
  rf._eofpos = nil -- clear before write
  local rowsz = assert(startrow(f, #v))
  assert(f:write(v))
  idx[i], rf._eofpos, cache[i] = pos, pos + rowsz + #v, v
end

CFile.__fmt = function(rf, f)
  f:write'civdb.CFile('
  if rf.path then f:write(rf.path) end
  f:write')'
end

return CFile

local mty = require'metaty'

--- binary row file with encoded length
local RowFile = mty'civdb.RowFile' {
  'f   [file]: open file', 'path [string]',
  'idx [lines.U3File]: row index of f',
  'cache [WeakV]: cache of rows',
  '_eofpos [nil|int]: nil or pos at eof',
}

local civdb = require'civdb'
local ds = require'ds'
local pth = require'ds.path'
local log = require'ds.log'
local lines = require'lines'
local LFile = require'lines.File'
local fd = require'fd'
local ix = require'civix'

local getmt = getmetatable
local index, newindex = mty.index, mty.newindex
local readrow, startrow = civdb.readrow, civdb.startrow

RowFile.IDX_DIR = pth.concat{pth.home(), '.data/rf'}
getmetatable(RowFile).__call    = getmetatable(LFile).__call
RowFile.close     = LFile.close
RowFile.flush     = LFile.flush
RowFile.__len     = LFile.__len
RowFile.__reader  = LFile.reader

RowFile._reindex = function(f, idx, r, pos)
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

getmetatable(RowFile).__index  = nil
RowFile.__index = function(rf, i)
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

RowFile.__newindex = function(rf, i, v)
  if type(i) == 'string' then return newindex(rf, i, v) end
  local f, idx, cache, pos = rf.f, rf.idx, rf.cache, rf._eofpos
  local pos = rf._eofpos or assert(f:seek'end')
  local len = #idx; assert(i == len + 1, 'only append allowed')
  rf._eofpos = nil -- clear before write
  local rowsz = assert(startrow(f, #v))
  assert(f:write(v))
  idx[i], rf._eofpos, cache[i] = pos, pos + rowsz + #v, v
end

RowFile.__fmt = function(rf, f)
  f:write'civdb.RowFile('
  if rf.path then f:write(rf.path) end
  f:write')'
end

return RowFile

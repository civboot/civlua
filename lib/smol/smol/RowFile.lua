local mty = require'metaty'

--- rf: binary row file
local RowFile = metaty'smol.RowFile' {
  'f   [file]: open file', 'path [string]',
  'idx [lines.U3File]: row index of f',
  'cache [WeakV]: cache of rows',
  '_rn  [int]:  current row num (false=end)',
  '_pos [bool]: current file pos',
}

local smol = require'smol'
local ds = require'ds'
local pth = require'ds.path'
local log = require'ds.log'
local lines = require'lines'
local LFile = require'lines.File'
local fd = require'fd'
local ix = require'civix'

local getmt = getmetatable
local index, newindex = mty.index, mty.newindex
local readrow, writerow = smol.readrow, smol.writerow

RowFile.IDX_DIR = pth.concat{pth.home(), '.data/rf'}
getmetatable(RowFile).__call    = getmetatable(LFile).__call
getmetatable(RowFile).close     = LFile.close
getmetatable(RowFile).flush     = LFile.flush
getmetatable(RowFile).__len     = LFile.__len
getmetatable(RowFile).__reader  = LFile.reader

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
  local row = cache[i]; if row then return row end
  local f, idx, pos, rowsz = rf.f, rf.idx, rf._pos
  if i > #idx then return end -- line num OOB
  if not pos or i ~= lf._rn then -- update file pos
    pos = assert(lf.idx[i])
    assert(f:seek('set', pos))
  end
  row, rowsz = readrow(f); assert(row, rowsz)
  rf._pos = pos + rowsz + #row
  rf._rn, cache[i] = i + 1, row
  return row
end

RowFile.__newindex = function(rf, i, v)
  if type(i) == 'string' then return newindex(rf, i, v) end
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache, lf._pos
  local len = #idx; assert(i == len + 1, 'only append allowed')
  if not pos or rf._rn then pos = assert(f:seek'end') end
  rf._rn, rf._pos = false, false
  local rowsz = assert(writerow(v))
  idx[i], rf._pos, cache[i] = pos, pos + rowsz, v
end

RowFile.__fmt = function(rf)
  push(fmt, 'smol.RowFile(')
  if rf.path then push(fmt, rf.path) end
  push(fmt, ')')
end

return M

local G = G or _G
--- utilities for file loading of lines.
local M = G.mod and mod'lines.futils' or {}

local fd = require'fd'
local ix = require'civix'
local U3File = require'lines.U3File'
local pth = require'ds.path'
local trace = require'ds.log'.trace

local TRUNC = {w=true, ['w+']=true}

--- load or reindex the file at path to/from idxpath.
M.loadIdx = function(f, idxpath, fmode, reindex) --> idxFile
  trace('loadIdx idxpath=%s mode=%s reindex=%q', idxpath, fmode, reindex)
  local fstat, xstat = assert(ix.stat(fd.fileno(f)))
  if TRUNC[fmode] then goto createnew end
  xstat = ix.stat(idxpath)
  if xstat and fd.modifiedEq(fstat, xstat) then
    return U3File:load(idxpath)
  end
  ::createnew::
  trace('loadIndex createnew')
  ix.mkDirs(pth.last(idxpath))
  local idx, err = U3File:create(idxpath)
  if not idx then return nil, err end
  reindex(f, idx)
  f:flush(); idx:flush()
  ix.setmodified(fd.fileno(idx.f), fstat:modified())
  return idx
end

return M

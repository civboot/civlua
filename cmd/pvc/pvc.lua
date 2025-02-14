local G = G or _G
local M = G.mod and mod'pvc' or setmetatable({}, {})

local mty = require'metaty'
local pth = require'ds.path'
local ix  = require'civix'
local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push = table.insert

local assertf = require'fmt'.assertf

--- the .pvc/ directory where data is stored
M.DOT = '.pvc/'
--- new file (used in unified diff label)
M.CREATED = '(created)'
--- deleted file (used in unified diff label)
M.DELETED = '(deleted)'

M.RESERVED_FILES = {
  [M.DOT]=1, [M.CREATED]=1, [M.DELETED]=1,
}
local checkFile = function(p)
  if not p then return end
  assert(not M.RESERVED_FILES[select(2, pth.last(p))], p)
  return p
end


--------------------------------
-- Patch Iterator

--- Access to a single patch.
--- Also acts as an iterator of patches
M.Patch = mty'Patches' {
  'id [int]: the current patch id',
  'path [string]: path to current patch id',
  'snap [string]: path to patch snapshot (if exists)',
  'minId [int]', 'maxId [int]',
  '_depth [int]: length of all change directories',
}

--- get or set depth (asserting it's valid)
M.Patch.depth = function(pch, d)
  if not d then return pch._depth end
  assert(d % 2 == 0); assert(d > 0); pch._depth = d
  return pch
end

--- given a patch id return it's common (non-merged) path
--- relative to [$branch/patches/]
M.Patch.patchPath = function(pch, id) --> path
  local dirstr = tostring(id)
  assertf(#dirstr <= pch._depth,
    '%i has longer length than depth=%i', id, pch._depth)
  dirstr = srep('0', pch._depth - #dirstr)..dirstr -- zero padded
  local path = {}; for i=1,#dirstr-2,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, id..'.p')
  return pth.concat(path)
end

--- Get next (id, path). Mutates id so it can be used as an iterator.
M.Patch.__call = function(pch) --> id, path
  local id = pch.id; if id > pch.maxId then return end
  pch.id = id + 1; return id, pch:patchPath(id)
end

--------------------------------
-- Utility functions

M.unix = G.mod and mod'pvc.unix' or {}
M.unix.diff = function(a, b, dir)
  dir = dir or ''
  a, b = checkFile(a) or M.CREATED, checkFile(b) or M.DELETED
  return ix.sh{
    -- take the diff
    'diff', pth.concat{dir, a}, pth.concat{dir, b},
    -- overwrite the label
    '--label='..a, '--label='..b,
    unified='1', stderr=io.stderr}
end

M.unix.patch = function(dir, patchPath)
end

return M

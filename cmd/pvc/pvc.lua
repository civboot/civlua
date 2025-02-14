local G = G or _G
local M = G.mod and mod'pvc' or setmetatable({}, {})

local mty = require'metaty'
local pth = require'ds.path'
local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push = table.insert

local assertf = require'fmt'.assertf

--- Access to a single patch.
--- Also acts as an iterator of patches
M.Patch = mty'Patches' {
  'id [int]: the current patch id',
  'path [string]: path to current patch id',
  'branch [string]: path to the branch',
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

return M

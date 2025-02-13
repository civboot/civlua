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
  'depth [int]: length of all change directories',
}

--- given a patch id return it's common (non-merged) path
--- relative to [$branch/patches/]
M.Patch.patchPath = function(pch, id) --> path
  local dirstr = tostring(id)
  assertf(#dirstr <= pch.depth,
    '%i has longer length than depth=%i', id, pch.depth)
  dirstr = srep('0', pch.depth - #dirstr)..dirstr -- zero padded
  local path = {}; for i=1,#dirstr-3,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, id..'.p')
  return pth.concat(path)
end

M.Patch.__call = function(pch)
  local nextid = pch.id + 1
  local nextfile = tostring(nextid);
  nextfile = srep('0', pch.depth - #nextfile)..nextfile
end

return M

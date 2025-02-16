local G = G or _G
local M = G.mod and mod'pvc' or setmetatable({}, {})

local mty = require'metaty'
local pth = require'ds.path'
local ix  = require'civix'
local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push = table.insert
local info = require'ds.log'.info

local assertf = require'fmt'.assertf
local NULL = '/dev/null'

--- the .pvc/ directory where data is stored
M.DOT = '.pvc/'

M.RESERVED_FILES = {
  [M.DOT]=1,
}
local checkFile = function(p)
  if not p then return end
  assert(not M.RESERVED_FILES[select(2, pth.last(p))], p)
  return p
end


M.toEconfig = function(t)
  local e = {}
  for k, v in pairs(t) do
    v = tostring(v); assert(not v:find'\n', 'newline in value')
    push(e, sconcat('=', k, v))
  end
  return table.concat(e, '\n')
end

M.fromEconfig = function(e)
  local t = {}; for line in ds.split(e, '\n') do
    local k, v = line:match'([^=])=(.*)'
    if k and v then t[k] = v end
  end
  return t
end

--------------------------------
-- Patch Iterator

--- Access to a single patch.
--- Also acts as an iterator of patches
M.Patch = mty'Patches' {
  'id [int]: the current patch id',
  'path [string]: path to current patch id',
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
-- Unix Version Control Functions
-- These shell out to unix for functionality instead of using civboot owned
-- algorithms.

M.unix = G.mod and mod'pvc.unix' or {}

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
M.unix.diff = function(dir, a, b)
  local aPath, bPath
  if not a then a, aPath = NULL, NULL
  else             aPath = pth.concat{dir or './', a} end
  if not b then b, bPath = NULL, NULL
  else             bPath = pth.concat{dir or './', b} end
  return ix.sh{
    'diff', '-N', aPath, '--label='..a, bPath, '--label='..b,
    unified='0', stderr=io.stderr}
end

local patchArgs = function(cwd, path)
  return {'patch', '-fu', input=path, CWD=cwd}
end

--- forward patch
M.unix.patch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-N')
  return ix.sh(args)
end

--- reverse patch
M.unix.rpatch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-R')
  return ix.sh(args)
end

--- incorporate all changes that went into going from base to change into to
M.unix.merge = function(to, base, change)
  return ix.sh{'merge', to, base, change}
end

local postCmd = {
  rename = function(a, b) info('rename %q %q', a, b); civix.mv(a, b) end,
  swap   = function(a, b) info('swap %q %q', a, b); civix.swap(a, b) end,
}

--- Given a patch string perform post-patch requirements in dir.
---
--- These must be given near the top of the patch file, before the first
--- [$---].  Supported commands (arguments are actually tab separated):
--- [##
--- ! rename before  after
--- ! swap   first   second
--- ]##
---
--- If reverse is given it does the opposite; also this should be called BEFORE
--- calling [$patch(reverse=true)]
M.patchPost = function(dir, patch, reverse)
  for line in ds.split(patch, '\n') do
    if line:sub(1,3) == '---' then return end -- stop after first diff
    if line:sub(1,1) == '!' then
      local cmd, a, b = table.unpack(ds.splitList(line:match'!%s*(.*)'))
      if reverse then a, b = b, a end
      (postCmd[cmd] or error('unknown cmd: '..cmd))(pth.concat{dir, a}, pth.concat{dir, b})
    end
  end
end

--------------------------------
-- PVC functions

--- reference to the id of a branch.
M.Ref = mty'Ref' { 'branch [string]', 'id [string]' }
M.Ref.__toPod = function(T, pset, ref)
  return table.concat({
    'BRANCH='..ref.branch,
    'ID='..ref.id,
    ref.url and ('URL='..ref.url) or nil,
  }, '\n')
end

--- base object which holds locations
M.PVC = mty'PVC' {
  'dir [string]: source code directory (user editable)',
  'dot [string]: typically dir/.pvc',
}
getmetatable(M.PVC).__call = function(T, t)
  assert(t.dir, 'must set dir')
  t.pvc = t.pvc or pth.concat{t.dir, M.DOT}
  return mty.construct(T, t)
end

--- get the path to branch
M.branchPath = function(pvc, name) return pth.concat{pvc.dot, name} end

M.newBranch = function(pvc, name, from)
  local p = pvc:branchPath(name)
  assertf(not ix.exists(p), 'branch %s already exists', name)
  ix.mkdir(pth.concat{p, 'patches'})
end

--- initialize a directory as a new PVC project
M.PVC.init = function(pvc, main)
end


M.init = function(dir, branch, from)
  local pvc = pth.concat{dir, M.DOT}
  if ix.exists(pvc) then error(dir..' already exists') end
  ix.mkdir(pvc)
  M.newbranch(branch or 'main', from)
end

return M

local G = G or _G
local M = G.mod and mod'pvc' or setmetatable({}, {})

local mty = require'metaty'
local ds  = require'ds'
local pth = require'ds.path'
local kev = require'ds.kev'
local ix  = require'civix'
local lines = require'lines'

local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push, concat = table.insert, table.concat
local info = require'ds.log'.info
local construct = mty.construct
local pconcat = pth.concat

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

--------------------------------
-- Patch Iterator

--- calculate necessary directory depth.
--- Example: 01/23/12345.p has dirDepth=4
M.calcDepth = function(id)
  local len = #tostring(id); if len <= 2 then return 0 end
  return len - (2 - (len % 2))
end

--- Reference to a single patch.
--- Also acts as an iterator of patches
M.Patch = mty'Patches' {
  'dir [string]', dir='',
  'id [int]: (required) the current patch id',
  'depth [int]: (required) length of all change directories',
}
getmetatable(M.Patch).__call = function(T, t)
  assert(t.id and t.depth, 'must set required fields')
  assert(t.depth >= 0 and t.depth % 2 == 0
     and M.calcDepth(t.id) <= t.depth , 'invalid depth')
  return construct(T, t)
end

--- Return the (non-merged) path relative to [$branch/patches/] of an id.
--- return nil if id is too large for [$depth]
M.Patch.path = function(pch, id) id=id or pch.id --> path?
  if M.calcDepth(id) > pch.depth then return end
  local dirstr = tostring(id):sub(1,-3)
  dirstr = srep('0', pch.depth - #dirstr)..dirstr -- zero padded
  local path = {pch.dir}; for i=1,#dirstr,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, id..'.p')
  return pconcat(path)
end

--- Get next (id, path). Mutates id so it can be used as an iterator.
M.Patch.__call = function(pch) --> id, path
  local id = pch.id; if M.calcDepth(id) > pch.depth then return end
  pch.id = id + 1; return id, pch:path(id)
end

--------------------------------
-- Unix Version Control Functions
-- These shell out to unix for functionality instead of using civboot owned
-- algorithms.

M.unix = G.mod and mod'pvc.unix' or {}

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
M.unix.diff = function(dir, a, b) --> string
  local aPath, bPath
  if not a then a, aPath = NULL, NULL
  else             aPath = pconcat{dir or './', a} end
  if not b then b, bPath = NULL, NULL
  else             bPath = pconcat{dir or './', b} end
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
      (postCmd[cmd] or error('unknown cmd: '..cmd))(pconcat{dir, a}, pconcat{dir, b})
    end
  end
end

-------------------------------
--- PVC Types

--- reference to the id of a branch.
M.Ref = mty'Ref' { 'branch [string]', 'id [string]', 'url [string]' }
getmetatable(M.Ref).__call = function(T, t)
    assert(t.branch, 'Ref must have branch')
    assert(t.id, 'Ref must have id')
    return mty.construct(T, t)
end

--------------------------------
-- Branch functions
M.Branch = mty'Branch' {
  'name [string]',
  'dir [string]: directory of branch',
}
M.Branch.exists = function(b) return ix.exists(b.dir) end
M.Branch.remove = function(b) ix.rmRecursive(b.dir)   end

--- Initialize the branch
M.Branch.init = function(b, ref) --> Branch
  if ref then ref = M.Ref(ref) end -- asserts valid
  assertf(not ix.exists(b.dir), 'branch %q already exists', b.name)
  local id = ref and ref.id or 0
  local depth = M.calcDepth(id + 50)
  local tree = {
    patch = {}, archive = {},
    files='', id=tostring(id), depth=tostring(depth),
  }
   if ref then
    tree.branch = concat(kev.to(ref), '\n')
    error'not implemented'
  else
    tree.patches = {
      [M.Patch{id=id, depth=depth}:path()..'.snap/'] = {}
    }
  end
  ix.mkTree(b.dir, tree, true)
  return b
end

local function integerFileMethod(name)
  return function(self, int)
    local path = self.dir..name
    if not int then return tonumber(pth.read(path)) end
    pth.write(path, tostring(int))
  end
end

--- get or set the id
M.Branch.id    = integerFileMethod'id'
--- get or set the depth
M.Branch.depth = integerFileMethod'depth'
--- Get or set list of files.
M.Branch.files = function(b, files) --> files?
  local fpath = b.dir..'files'
  if not files then return lines.load(fpath) end
  return lines.dump(ds.sortUnique(files), fpath)
end

--- Get the Patch at the id
M.Branch.patch = function(b, id)id=id or b.id() --> Patch
  return M.Patch{dir=b.dir..'patches/', id=id, depth=b.depth()}
end

M.Branch.commit = function(b)
  local id = b:id()

  for i, path in b:files() do
  end

  b:id(id + 1)
end

--------------------------------
-- PVC functions

--- base object which holds locations
M.PVC = mty'PVC' {
  'dir [string]: source code directory (user editable)',
  'dot [string]: typically dir/.pvc',
}
getmetatable(M.PVC).__call = function(T, t)
  assert(t.dir, 'must set dir')
  t.dot = pconcat{t.dot or pconcat{t.dir, M.DOT}, '/'}
  return mty.construct(T, t)
end

--- Get a branch object. The branch may or may not exist.
M.PVC.branch = function(p, name) --> Branch
  return M.Branch{name=name, dir=pconcat{p.dot, name, '/'}}
end

--- initialize a directory as a new PVC project
M.PVC.init = function(p) --> p
  if not ix.exists(p.dir) then error(p.dir' does not exist') end
  if ix.exists(p.dot) then error(p.dot..' already exists') end
  ix.mkDir(p.dot)
  return p
end

----------------
-- API

--- get a PVC object from a directory
M.load = function(dir) return M.PVC{dir=dir} end

--- initialize a directory as PVC
M.init = function(dir, branch, ref)
  if ref then error'unimplemented' end
  local p = M.load(dir):init()
  p:branch(branch or 'main'):init(ref)
  return p
end

return M

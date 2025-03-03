local G = G or _G
local M = G.mod and mod'pvc' or setmetatable({}, {})

local mty = require'metaty'
local ds  = require'ds'
local pth = require'ds.path'
local kev = require'ds.kev'
local ix  = require'civix'
local lines = require'lines'
local T = require'civtest'.Test

local pu = require'pvc.unix'

local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push, concat = table.insert, table.concat
local info = require'ds.log'.info
local trace = require'ds.log'.trace
local construct = mty.construct
local pconcat = pth.concat

local assertf = require'fmt'.assertf

--- the .pvc/ directory where data is stored
M.DOT = '.pvc/'

M.PVCPATHS = '.pvcpaths' -- file
M.INIT_PVCPATHS = '.pvcpaths\n' -- initial contents
M.INIT_PATCH = [[
# initial patch
--- /dev/null
+++ .pvcpaths
.pvcpaths
]]

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
  'dir [string]: .../patch/ directory',
  'id [int]: (required) the current patch id',
  'depth [int]: (required) length of all change directories',
}
getmetatable(M.Patch).__call = function(T, t)
  assert(t.id and t.depth, 'must set required fields')
  assert(t.depth >= 0 and t.depth % 2 == 0
     and M.calcDepth(t.id) <= t.depth , 'invalid depth')
  return construct(T, t)
end

--- get the path to the raw id (without [$.p] extension)
M.Patch.rawpath = function(pch, id) --> path?
  if not id then id = pch.id end
  if M.calcDepth(id) > pch.depth then return end
  local dirstr = tostring(id):sub(1,-3)
  dirstr = srep('0', pch.depth - #dirstr)..dirstr -- zero padded
  local path = {}; for i=1,#dirstr,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, tostring(id))
  return pconcat(path)
end

--- Return the (non-merged) path relative to [$branch/patch/] of an id.
--- return nil if id is too large for [$depth]
M.Patch.path = function(pch, id) --> path?
  local r = pch:rawpath(id); return r and (r..'.p') or nil
end

--- return the snapshot directory path of patch id.
M.Patch.snap = function(pch, id) --> path?
  local r = pch:rawpath(id); return r and (r..'.snap/') or nil
end

--- [$full'path'] gets the full.p, [$full'snap'] gets the full.snap/
M.Patch.full = function(pch, name, id)
  return pch.dir..pch[name](pch, id)
end

--- Get next (id, path). Mutates id so it can be used as an iterator.
M.Patch.__call = function(pch) --> id, path
  local id = pch.id; if M.calcDepth(id) > pch.depth then return end
  pch.id = id + 1; return id, pch:path(id)
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

--- Prepare [$patch/] to accept [$path] of form [$01/23/45/patch.p]
M.Branch.initPatch = function(b, path, depth) --> patchDir/
  assert(not pth.isDir(path))
  depth = depth or b:depth()
  local dir, plist = b.dir..'patch/', pth(path)
  trace('plist %q', plist)
  T.eq(depth, (#plist - 1) * 2)
  local i = 1; while true do
    local dpath = dir..'depth'
    if not ix.exists(dir) then trace('mkDir', dir); ix.mkDir(dir) end
    if ix.exists(dpath)   then T.eq(depth, tonumber(pth.read(dpath)))
    else
      trace('%i > %s', depth, dpath); pth.write(dpath, tostring(depth))
    end
    print('!! i', i, plist[i])
    if i >= #plist then return path end
    local c = plist[i]
    if not c:find'^%d%d$' then error('invalid dir path: '..path) end
    dir = pth.concat{dir, c, '/'};
    depth = depth - 2
    i = i + 1
  end
end

--- Initialize the branch
M.Branch.init = function(b, ref) --> Branch
  if ref then ref = M.Ref(ref) end -- asserts valid
  assertf(not ix.exists(b.dir), 'branch %q already exists', b.name)
  local id = ref and ref.id or 0
  local depth = M.calcDepth(id + 1000)
  local tree = {
    patch = {}, archive = {},
    files='', id=tostring(id),
  }
  trace('mkTree', b.dir)
  ix.mkTree(b.dir, tree, true)
  local p = b:patch(id, depth)
  b:initPatch(p:path(), depth)
  local patch = b.dir..'patch/'
  if ref then error'not implemented'
  else assert(id == 0)
    local ppath, spath = patch..p:path(), patch..p:snap()
    local mpath = pth.last(pth.last(b.dir))..M.PVCPATHS
    trace('init 0: %s %s', mpath, ppath)
    pth.write(patch..p:path(), M.INIT_PATCH)
    ix.mkTree(patch..p:snap(), {
      PVC_DONE = '', [M.PVCPATHS] = M.INIT_PVCPATHS,
    })
    pth.write(mpath, M.INIT_PVCPATHS)
  end
  return b
end

--- get or set the id
M.Branch.id    = function(b, id)
  local path = b.dir..'id'
  if not id then return tonumber(pth.read(path)) end
  pth.write(path, tostring(id))
end
--- get the depth
M.Branch.depth = function(b)
  return tonumber(pth.read(b.dir..'patch/depth'))
end

--- increase depth of branch
M.Branch.deeper = function(b)
  -- make patch/00 where 00/ is the previous patch/
  local depth, pp, zz = b:depth(), b.dir..'patch/', b.dir..'00/'
  ix.mv(pp, zz); ix.mkDir(pp) ix.mv(zz, pp)
  pth.write(pp..'depth', tostring(depth + 2))
end

--- Get the Patch at the id
M.Branch.patch = function(b, id, depth) --> Patch
  return M.Patch{
    dir=b.dir..'patch/',
    id=id or b:id(), depth=depth or b:depth(),
  }
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

--- Get or set the current branch and (optional) id
M.PVC.head = function(p, name, id) --> Branch?, Patch?
  local hpath = p.dot..'head'
  if not name then
    local h = kev.load(hpath)
    local b = p:branch(assert(h.branch))
    return b, b:patch(h.id and tonumber(h.id))
  end
  kev.dump({branch=name, id=tostring(id)}, hpath)
end

--- initialize a directory as a new PVC project
M.PVC.init = function(p, branch, ref) --> p
  branch = branch or 'main'
  info('init %q ref=%q', branch, ref)
  if not ix.exists(p.dir) then error(p.dir' does not exist') end
  if ix.exists(p.dot) then error(p.dot..' already exists') end
  trace('mkDir %s', p.dot)
  ix.mkDir(p.dot)
  p:branch(branch or 'main'):init(ref)
  p:head('main', ref and ref.id or 0)
  return p
end

--- Get or set the working paths
M.PVC.paths = function(p, paths) --> paths?
  local ppath = p.dir..M.PVCPATHS
  if not paths then return lines.load(ppath) end
  if paths[#paths] == '' then paths[#paths] = nil end
  paths = ds.sortUnique(paths)
  push(paths, '')
  return lines.dump(paths, ppath)
end

M.PVC.addPaths = function(p, paths) --> PVC
  local fpaths = p:paths()
  for _, ap in pairs(paths) do push(fpaths, ap) end
  p:paths(fpaths)
end

local mpush = function(t, v)
  if v == nil then return else push(t, v) end
end

M.PVC.commit = function(p) --> Branch, Patch
  local b, pat = p:head(); local nxt = ds.copy(pat)
  if nxt() == nil then
    b:deeper()
    pat, nxt = b:patch(pat.id), b.patch(pat.id+1)
  end
  local cur, snap = p.dir, pat:full'snap'
  trace('commit compare: %s', snap)
  assert(ix.exists(snap), 'TODO: checkout')

  local post, ptext, paths = {}, {'# message', '(post)'}, {}
  for i, path in ipairs(p:paths()) do
    if paths[path] then goto cont end; paths[path] = true
    local d = pu.diff(snap..path, path, cur..path, path)
    print('!! diff of', path); print(d)
    if d then push(ptext, d) end
    ::cont::
  end
  -- look for removed paths
  for i, path in ipairs(lines.load(snap..M.PVCPATHS)) do
    if not paths[path] then
      push(ptext, pu.diff('', cpath, nil))
      paths[path] = true
    end
  end
  ptext[2] = concat(post, '\n')
  local path = nxt:full'path'
  pth.write(path, concat(ptext, '\n'))
  info('created patch %s', path)

  -- FIXME: create snap by applying the patch then validating
  -- all the files are identical

  b:id(nxt.id)
  return b, nxt
end


----------------
-- API

--- initialize a directory as PVC
M.init = function(dir, branch, ref)
   return M.PVC{dir=dir}:init(branch, ref)
end

return M

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
local sort = table.sort
local info = require'ds.log'.info
local trace = require'ds.log'.trace
local s = ds.simplestr
local construct = mty.construct
local pconcat = pth.concat

local assertf = require'fmt'.assertf

--- the .pvc/ directory where data is stored
M.DOT = '.pvc/'
M.PVC_DONE = 'PVC_DONE'

M.PVCPATHS = '.pvcpaths' -- file
M.INIT_PVCPATHS = '.pvcpaths\n' -- initial contents
M.INIT_PATCH = [[
# initial patch
--- /dev/null
+++ .pvcpaths
.pvcpaths
]]

--- reserved branch names
M.RESERVED_NAMES = { ['local']=1, head=1, tip=1, }

--- get a set of the lines in a file
local loadLineSet = function(path) --> set
  local s = {}; for l in io.lines(path) do s[l] = true end; return s
end

M.RESERVED_FILES = {
  [M.DOT]=1,
}
local checkFile = function(p)
  if not p then return end
  assert(not M.RESERVED_FILES[select(2, pth.last(p))], p)
  return p
end

local forceCp = function(from, to)
  ix.rmRecursive(to); ix.mkDirs( (pth.last(to)) )
  ix.cp(from, to)
end

--- copy all paths in [$from/.pvcpaths] -> [$to/]
local cpPaths = function(from, to)
  trace('cpPaths %s -> %s', from, to)
  for path in io.lines(from..M.PVCPATHS) do
    forceCp(from..path, to..path)
  end
end

--- [$Diff:of(dir1, dir2)] returns what changed between two pvc dirs.
M.Diff = mty'Diff' {
  'dir1 [string]', 'dir2 [string]',
  'equal   [list]',
  'changed [list]',
  'deleted [list]',
  'created [list]',
}
M.Diff.of = function(T, dir1, dir2)
  local t = (type(dir1) == 'table') and dir1 or {dir1=dir1, dir2=dir2}
  t = T(t)
  local equal, changed, deleted, created = {}, {}, {}, {}
  local paths1 = loadLineSet(t.dir1..M.PVCPATHS)
  local paths2 = loadLineSet(t.dir2..M.PVCPATHS)
  for path in pairs(paths1) do
    if paths2[path] then
      if ix.pathEq(dir1..path, dir2..path) then push(equal, path)
      else                                    push(changed, path) end
    else push(deleted, path) end
  end
  for path in pairs(paths2) do
    if not paths1[path] then push(created, path) end
  end
  sort(equal); sort(changed); sort(deleted); sort(created)
  t.equal, t.changed, t.deleted, t.created =
    equal,   changed,   deleted,   created
  return t
end
M.Diff.format = function(d, fmt)
  if (#d.changed == 0) and (#d.deleted == 0) and (#d.created == 0) then
    return fmt:styled('bold', 'No Difference')
  end
  fmt:styled('bold', 'Diff:', ' ', d.dir1, ' --> ', d.dir2, '\n')
  for _, path in ipairs(d.deleted) do
    fmt:styled('base',   '-'..path, '\n')
  end
  for _, path in ipairs(d.created) do
    fmt:styled('change', '-'..path, '\n')
  end
  for _, path in ipairs(d.changed) do
    fmt:styled('notify', '~'..path, '\n')
  end
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
  for line in io.lines(patch) do
    if line:sub(1,3) == '---' then break end -- stop after first diff
    if line:sub(1,1) == '!' then
      local cmd, a, b = table.unpack(ds.splitList(line:match'!%s*(.*)'))
      if reverse then a, b = b, a end
      (postCmd[cmd] or error('unknown cmd: '..cmd))(pconcat{dir, a}, pconcat{dir, b})
    end
  end
end

--- forward patch, applying diff to dir
M.patch = function(dir, diff)
  pu.patch(dir, diff)
  M.patchPost(dir, diff)
end

--- reverse patch, applying diff to dir
M.rpatch = function(dir, diff)
  M.patchPost(dir, diff, true)
  pu.rpatch(dir, diff)
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
M.Branch.ref    = function(b, id)
  return M.Ref{branch=b.name, id=id or b:tip()}
end

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
    if i >= #plist then return path end
    local c = plist[i]
    if not c:find'^%d%d$' then error('invalid dir path: '..path) end
    dir = pth.concat{dir, c, '/'};
    depth = depth - 2
    i = i + 1
  end
end

--- Initialize the branch
M.Branch.init = function(b, id) --> Branch
  assert(id >= 0)
  assertf(not ix.exists(b.dir), 'branch %q already exists', b.name)
  local depth = M.calcDepth(id + 1000)
  local tree = {
    patch = {depth=tostring(depth)},
    archive = {},
    files='', id=tostring(id), tip=tostring(id),
  }
  trace('mkTree %s', b.dir); ix.mkTree(b.dir, tree, true)
  if id ~= 0 then return b end
  local p = b:patch(id, depth)
  b:initPatch(p:path(), depth)
  local patch = b.dir..'patch/'
  local ppath, spath = patch..p:path(), patch..p:snap()
  local mpath = pth.last(pth.last(b.dir))..M.PVCPATHS
  trace('init %s/0: %s %s', b.name, mpath, ppath)
  pth.write(patch..p:path(), M.INIT_PATCH)
  ix.mkTree(patch..p:snap(), {
    [M.PVC_DONE] = '', [M.PVCPATHS] = M.INIT_PVCPATHS,
  })
  pth.write(mpath, M.INIT_PVCPATHS)
  return b
end

--- find closest snapshot to id (either forward or backward)
M.Branch.findSnap = function(b, id, tip) --!!> id, snapDir
  local snap = b:patch(id):full'snap'
  if ix.exists(snap..M.PVC_DONE) then
    trace('snap %s already exists', id)
    return id, snap
  end
  trace('searching for closest snap %s/%s', b.name, id)
  tip = tip or b:tip()
  local pl, pr = b:patch(id - 1), b:patch(id + 1)
  while (0 <= pl.id) or (pr.id <= tip) do
    snap = pl:full'snap'
    if pl.id >= 0   and ix.exists(snap..M.PVC_DONE) then
      return pl.id, snap
    end
    snap = pr:full'snap'
    if pr.id <= tip and ix.exists(snap..M.PVC_DONE) then
      return pr.id, snap
    end
    pl.id, pr.id = pl.id - 1, pr.id + 1
  end
  error'unable to find a .snap/'
end

--- Create a snapshot by applying patches
M.Branch.snapshot = function(b, id) --> dir
  id = id or b:tip()
  -- f=from, t=to
  local fid, fsnap = b:findSnap(id); if id == fid then return fsnap end
  trace('closest snap to %s/%s is %s', b.name, id, fid)
  local tip, tsnap = b:tip(), b:patch(id):full'snap';
  trace('creating snapshot %s from %s', tsnap, fsnap)
  if ix.exists(tsnap) then ix.rmRecursive(tsnap) end
  ix.mkDir(tsnap)
  cpPaths(fsnap, tsnap)
  local patch = (fid <= id) and M.patch or M.rpatch
  local inc   = (fid <= id) and 1       or -1
  fid = fid + inc
  while true do
    patch(tsnap, b:patch(fid):full'path')
    if fid == id then break end
    fid = fid + inc
  end
  pth.write(tsnap..M.PVC_DONE, '')
  info('created snapshot %s', tsnap)
  return tsnap
end

--- get or set the tip id
M.Branch.tip    = function(b, id)
  local path = b.dir..'tip'
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
    id=id or b:tip(), depth=depth or b:depth(),
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
M.PVC.getBranch = function(p, name) --> Branch
  if M.RESERVED_NAMES[name] then error('reserved branch name: '..name) end
  return M.Branch{name=name, dir=pconcat{p.dot, name, '/'}}
end

--- Get or set the current branch and (optional) id
M.PVC.head = function(p, name, id) --> Branch?, Patch?
  local hpath = p.dot..'head'
  if not name then
    local h = kev.load(hpath)
    local b = p:getBranch(assert(h.branch))
    return b, b:patch(h.id and tonumber(h.id))
  end
  kev.dump({branch=name, id=tostring(id)}, hpath)
end

--- create new branch from (local) head and check it out
M.PVC.branch = function(p, name) --> Branch, Pat
  local nb = p:getBranch(name) -- n=new
  local ob, opat = p:head()    -- o=old
  info('branching %s from %s/%s', name, ob.name, opat.id)
  nb:init(opat.id)
  local npat = nb:patch(opat.id)
  local osnap, nsnap = opat:full'snap', npat:full'snap'
  cpPaths(osnap, nsnap); pth.write(nsnap..M.PVC_DONE, '')
  p:head(name, opat.id)
  return nb, npat
end

--- initialize a directory as a new PVC project
M.PVC.init = function(p, branch, url) --> p
  assert(not url, 'unimplemented')
  branch = branch or 'main'
  info('init %q', branch)
  if not ix.exists(p.dir) then error(p.dir' does not exist') end
  if ix.exists(p.dot) then error(p.dot..' already exists') end
  trace('mkDir %s', p.dot)
  ix.mkDir(p.dot)
  p:getBranch(branch or 'main'):init(0)
  p:head('main', 0)
  return p
end


--- Return the [$pvc.Diff] of br1/id1 with br2/id2.
--- A nil value for br1 is head
--- A nil value for br2 is local
M.PVC.diff = function(p, br1, id1, br2, id2) --> pvc.Diff
  local dir1, dir2, pat
  if br1 == 'local'            then dir1 = p.dir end
  if not br1 or br1 == 'head'  then
    br1, pat = p:head();
    dir1 = assert(br1:snapshot(pat.id), 'could not find br1')
  end

  if br2 == 'head' then
    br2, pat = p:head()
    dir2 = assert(br2:snapshot(pat.id), 'could not find br2')
  end
  if not br2 or br2 == 'local' then dir2 = p.dir end

  return M.Diff:of(
    dir1 or p:getBranch(br1):snapshot(id1),
    dir2 or p:getBranch(br2):snapshot(id2))
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

--- call [$fn(path1, path2)] for all files in [$dir/.pvcpaths]
--- the value will be nil if it is missing in either path.
---
--- Note: the passed in paths are still relative.
local mapPvcPaths = function(dir1, dir2, fn)
  local paths1, paths2 = {}, {}
  for p in io.lines(dir1..M.PVCPATHS) do paths1[p] = 1 end
  for p in io.lines(dir2..M.PVCPATHS) do paths2[p] = 1 end
  for p1 in pairs(paths1) do fn(p1, paths2[p1] and p1 or nil) end
  for p2 in pairs(paths2) do
    if not paths1[p2] then fn(nil, p2) end
  end
end

M.PVC.checkout = function(p, branch, id)
  local f, ldir = io.fmt, p.dir -- l=local

  -- c=current branch/pat/dir
  local cb, cpat = p:head(); local cdir = cpat:full'snap'

  -- n=next branch/pat/dir
  local nb = p:getBranch(branch)
  nb:snapshot(id)
  local npat = nb:patch(id); local ndir = npat:full'snap'

  local lpaths = loadLineSet(ldir..M.PVCPATHS)
  local cpaths = loadLineSet(cdir..M.PVCPATHS)
  local npaths = loadLineSet(ndir..M.PVCPATHS)

  local ok, cpPaths, rmPaths = true, {}, {}
  for path in pairs(npaths) do
    if ix.pathEq(ldir..path, ndir..path) then goto cont end -- local==next
    if ix.pathEq(ldir..path, cdir..path) then -- local didn't change
      if not ix.pathEq(cdir..path, ndir..path) then -- next did change
        push(cpPaths, path)
      end; goto cont
    end
    -- else local path changed
    if ix.pathEq(cdir..path, ndir..path) then
      f:styled('meta', sfmt('keeping changed %s', path), '\n')
    else
      f:styled('error', sfmt('path %s changed', path), '\n')
      ok = false
    end
    ::cont::
  end
  -- look at paths in current but not next
  for path in pairs(cpaths) do
    if npaths[path]              then goto cont end
    if not ix.exists(ldir..path) then goto cont end -- already deleted
    if ix.pathEq(ldir..path, cdir..path) then push(rmPaths, path)
    else
      f:styled('error',
        sfmt('path %s changed but would be removed', path), '\n')
      ok = false
    end
    ::cont::
  end
  if not ok then error(s[[
    ERROR: local changes would be trampled by checkout. Solutions:
    * commit the current changes
    * revert the current changes
  ]]) end
  for _, path in ipairs(cpPaths) do
    trace('checkout cp: %s', path)
    forceCp(ndir..path, ldir..path)
  end
  for _, path in ipairs(rmPaths) do
    trace('checkout rm: %s', path)
    ix.rmRecursive(ldir..path)
  end
  info('checked out %s/%s', branch, id)
  p:head(branch, id)
end

M.PVC.commit = function(p) --> Branch, Patch
  local b, pat = p:head(); local tip = b:tip()
  trace('commit from %s/%s', pat.id, tip)
  if pat.id ~= tip then error(s[[
    ERROR: current head is not at tip. Solutions:
    * stash -> checkout head -> unstash -> commit
    * prune <my new branch>: move downstream changes to new branch.
  ]])end

  local nxt = ds.copy(pat); if nxt() == nil then
    b:deeper()
    pat, nxt = b:patch(pat.id), b.patch(pat.id+1)
  end
  local snap = b:snapshot(pat.id); trace('base snap: %s', snap)

  local post, ptext, paths = {}, {'# message', '(post)'}, {}
  for i, path in ipairs(p:paths()) do
    if paths[path] then goto cont end; paths[path] = true
    local d = pu.diff(snap..path, path, p.dir..path, path)
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
  pth.write(path, concat(ptext, '\n')); info('created patch %s', path)
  local nsnap = b:snapshot(nxt.id)
  for path in io.lines(p.dir..M.PVCPATHS) do
    T.pathEq(nsnap..path, p.dir..path)
  end

  b:tip(nxt.id); p:head(b.name, nxt.id)
  info('successfully commited %s/%s', b.name, nxt.id)
  return b, nxt
end

----------------
-- API

--- initialize a directory as PVC
M.init = function(dir, branch, ref)
   return M.PVC{dir=dir}:init(branch)
end

return M

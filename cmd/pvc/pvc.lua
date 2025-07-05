local G = G or _G
local M = G.mod and mod'pvc2' or setmetatable({}, {})
MAIN = G.MAIN or M

local shim  = require'shim'
local mty   = require'metaty'
local ds    = require'ds'
local pth   = require'ds.path'
local kev   = require'ds.kev'
local ix    = require'civix'
local lines = require'lines'
local T = require'civtest'

local pu = require'pvc.unix'

local srep, sfmt = string.rep, string.format
local sconcat = string.concat
local push, concat = table.insert, table.concat
local sort = table.sort
local info = require'ds.log'.info
local trace = require'ds.log'.trace
local s = ds.simplestr
local construct = mty.construct
local toDir, pconcat = pth.toDir, pth.concat
local pk = ds.popk

local assertf = require'fmt'.assertf

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

local toint = math.tointeger

--- this exists for tests to override
M.backupId = function() return tostring(ix.epoch():asSeconds()) end

--- reserved branch names
M.RESERVED_NAMES = { ['local']=1, at=1, tip=1, }

-----------------------------------
-- Utilities

--- get a set of the lines in a file
local loadLineSet = function(path) --> set
  local s = {}; for l in io.lines(path) do s[l] = true end; return s
end

local loadPaths = function(P) --> list
  local paths = ds.BiMap(lines.load(P..M.PVCPATHS))
  if not paths[M.PVCPATHS] then push(paths, M.PVCPATHS) end
  return paths
end

local loadIgnore = function(P) --> list
  local ignore = {'%./%.pvc/'}
  for line in io.lines(P..'.pvcignore') do
    if line == '' or line:sub(1,1) == '#' then --ignore
    else push(ignore, line)
    end
  end
  return ignore
end

--- copy all paths in [$from/.pvcpaths] -> [$to/]
local cpPaths = function(from, to)
  trace('cpPaths %s -> %s', from, to)
  for path in io.lines(from..M.PVCPATHS) do
    ix.forceCp(from..path, to..path)
  end
end

local readInt = function(path) return toint(pth.read(path)) end

--- call [$fn(path1, path2)] for all files in [$dir/.pvcpaths]
--- the value will be nil if it is missing in either path.
---
--- Note: the passed in paths are still relative.
local mapPvcPaths = function(dir1, dir2, fn)
  local paths1, paths2 = loadPaths(dir1), loadPaths(dir2)
  for _, p1 in ipairs(paths1) do fn(p1, paths2[p1] and p1 or nil) end
  for _, p2 in ipairs(paths2) do
    if not paths1[p2] then fn(nil, p2) end
  end
end

local untracked = function(P) --> list[string]
  trace('untracked %s', P)
  local out, paths, ignore = {}, ds.Set(loadPaths(P)), loadIgnore(P)
  local w = ix.Walk{P}
  for path, fty in w do
    path = path:sub(#P+1)
    if path == '' then goto cont end
    local mpath = './'..path -- path for matching
    trace('ut path %q', mpath)
    if paths[path] then goto cont end
    if fty == 'dir' then
      for _, pat in ipairs(ignore) do
        if pat:sub(-1,-1) == '/' and mpath:find(pat) then
          w:skip(); goto cont
        end
      end
    else
      for _, pat in ipairs(ignore) do
        if pat:sub(-1,-1) ~= '/' and mpath:find(pat) then
          goto cont
        end
      end
      push(out, path)
    end
    ::cont::
  end
  table.sort(out)
  return out
end


-----------------------------------
-- Patch Logic

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

--- calculate necessary directory depth.
--- Example: 01/23/12345.p has dirDepth=4
M.calcPatchDepth = function(id)
  local len = #tostring(id); if len <= 2 then return 0 end
  return len - (2 - (len % 2))
end

-----------------------------------
-- Diff

--- [$Diff:of(dir1, dir2)] returns what changed between two pvc dirs.
M.Diff = mty'Diff' {
  'dir1 [string]', 'dir2 [string]',
  'equal   [list]',
  'changed [list]',
  'deleted [list]',
  'created [list]',
}

M.Diff.of = function(T, d1, d2)
  local peq = ix.pathEq
  local t = (type(d1) == 'table') and d1 or {dir1=d1, dir2=d2}
  t = T(t)
  local equal, changed, deleted, created = {}, {}, {}, {}
  mapPvcPaths(d1, d2, function(p1, p2)
    if p1 and p2 then
      if peq(d1..p1, d2..p2) then push(equal,   p1)
      else                        push(changed, p1) end
    elseif p1 then                push(deleted, p1)
    else                          push(created, p2)
    end
  end)
  sort(equal); sort(changed); sort(deleted); sort(created)
  t.equal, t.changed, t.deleted, t.created =
    equal,   changed,   deleted,   created
  return t
end

M.Diff.hasDiff = function(d)
  return (#d.changed > 0) or (#d.deleted > 0) or (#d.created > 0)
end

M.Diff.format = function(d, fmt, full)
  local function s(...) return fmt:styled(...) end
  if full then
    for _, line in ds.split(d:patch(), '\n') do
      local l2 = line:sub(1,2)
      if l2 == '--' or l2 == '++' or l2 == '@@' then s('notify', line, '\n')
      elseif line:sub(1,1) == '-' then s('base',   line, '\n')
      elseif line:sub(1,1) == '+' then s('change', line, '\n')
      else fmt:write(line, '\n') end
    end
  else
    if not d:hasDiff() then return s('bold', 'No Difference') end
    s('bold', 'Diff:', ' ', d.dir1, ' --> ', d.dir2, '\n')
    for _,path in ipairs(d.deleted) do s('base',   '-'..path, '\n') end
    for _,path in ipairs(d.created) do s('change', '+'..path, '\n') end
    for _,path in ipairs(d.changed) do s('notify', '~'..path, '\n') end
  end
end

M.Diff.patch = function(d) --> patchText
  local d1, d2, patch = d.dir1, d.dir2, {}
  for _, path in ipairs(d.changed) do
    push(patch, pu.diff(d1..path, path, d2..path, path))
  end
  for _, path in ipairs(d.created) do
    push(patch, pu.diff(nil, nil, d2..path, path))
  end
  for _, path in ipairs(d.deleted) do
    push(patch, pu.diff(d1..path, path))
  end
  return concat(patch, '\n')
end

--------------------------------------------
-- Branch

--- return the branch path in project regardless of whether it exists
M.branchDir = function(P, branch, dot)
  assert(branch, 'branch is nil')
  assert(not M.RESERVED_NAMES[branch], 'branch name is reserved')
  return pth.concat{P, dot or '.pvc', branch, '/'}
end

M.getbase = function(bdir, br) --> br, id
  local bpath = bdir..'base'
  if ix.exists(bpath) then return M.parseBranch(pth.read(bpath))
  else return br, 0 end
end
M.rawtip = function(bdir, id)
  if id then pth.write(toDir(bdir)..'tip', tostring(id))
  else return readInt(toDir(bdir)..'tip') end
end
M.depth = function(bdir) return readInt(toDir(bdir)..'commit/depth') end

M.patchPath = function(bdir, id, last, depth) --> string?
  depth = depth or M.depth(bdir)
  if M.calcPatchDepth(id) > depth then return end
  local dirstr = tostring(id):sub(1,-3)
  dirstr = srep('0', depth - #dirstr)..dirstr -- zero padded
  local path = {bdir, 'commit'}; for i=1,#dirstr,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, tostring(id)..(last or '.p'))
  return pconcat(path)
end

--- Get the snap/ path regardless of whether it exists
M.snapDir = function(bdir, id) --> string?
  return M.patchPath(bdir, id, '.snap/')
end

local function initSnap0(snap)
  ix.forceWrite(snap..M.PVCPATHS, M.INIT_PVCPATHS)
  ix.forceWrite(snap..'PVC_DONE', '')
end

local function initBranch(bdir, id)
  assert(id >= 0)
  assertf(not ix.exists(bdir), '%s already exists', bdir)
  local depth = M.calcPatchDepth(id + 1000)
  trace('initbranch %s', bdir)
  ix.mkTree(bdir, {
    tip=tostring(id), commit = {depth=tostring(depth)},
  }, true)
  if id ~= 0 then return bdir end
  local ppath = M.patchPath(bdir, id, '', depth)
  initSnap0(ppath..'.snap/')
end

--- Snapshot the branch#id by applying patches.
--- Return the snapshot directory
M.snapshot = function(P, br,id) --> .../id.snap/
  trace('snapshot %s#%s', br,id)
  -- f=from, t=to
  local bdir = M.branchDir(P, br)
  local snap = M.snapDir(bdir, id)
  if ix.exists(snap) then return snap, id end
  if id == 0 then return initSnap0(snap) end
  local bbr,bid = M.getbase(bdir, br)
  if id == bid then return M.snapshot(P, bbr,bid) end
  trace('findSnap %s id=%s with base %s#%s', bdir, id, bbr,bid)

  local tip      = M.rawtip(bdir)
  local fsnap, fid -- find the snap/id to patch from
  local idl, idr = id-1, id+1
  while (bid <= idl) or (idr <= tip) do
    snap = M.patchPath(bdir, idl, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = M.snapDir(bdir,idl), idl; break
    end
    if bid == idl then
      fsnap, fid = M.snapshot(P, bbr,bid), idl; break
    end
    snap = M.patchPath(bdir, idr, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = M.snapDir(bdir,idr), idr; break
    end
    idl, idr = idl-1, idr+1
  end
  if not fsnap then error(bdir..' does not have snapshot '..id) end
  local tsnap = M.snapDir(bdir, id)
  trace('creating snapshot %s from %s', tsnap, fsnap)
  if ix.exists(tsnap) then ix.rmRecursive(tsnap) end
  ix.mkDir(tsnap)
  cpPaths(fsnap, tsnap)
  local patch = (fid <= id) and pu.patch or pu.rpatch
  local inc   = (fid <= id) and 1       or -1
  fid = fid + inc
  while true do
    local ppath = M.patchPath(bdir, fid)
    trace('patching %s with %s', tsnap, ppath)
    patch(tsnap, ppath)
    if fid == id then break end
    fid = fid + inc
  end
  pth.write(tsnap..M.PVC_DONE, '')
  info('created snapshot %s', tsnap)
  return tsnap
end

--- increase the depth of branch by 2, adding a [$00/] directory.
M.deepen = function(bdir)
  local depth, pp, zz = M.depth(bdir), bdir..'commit/', bdir..'00/'
  ix.mv(pp, zz); ix.mkDir(pp) ix.mv(zz, pp)
  pth.write(pp..'depth', tostring(depth + 2))
end

-----------------
-- Project Methods

M.parseBranch = function(str, bdefault, idefault) --> branch, id
  local i = str:find'#'
  if i              then return str:sub(1,i-1), toint(str:sub(i+1))
  elseif toint(str) then return bdefault,       toint(str)
  else                   return str,            idefault end
end

--- get or hard set the current branch/id
M.rawat = function(P, branch, id)
  local apath = pth.concat{P, '.pvc/at'}
  if branch then pth.write(apath, sfmt('%s#%s', branch, id))
  else    return M.parseBranch(pth.read(apath)) end
end

--- get or set where the working id is at.
M.at = function(P, nbr,nid) --!!> branch?, id?
  -- c=current, n=next
  local cbr, cid = M.rawat(P); if not nbr then return cbr, cid end
  local npath = M.branchDir(P, nbr)

  nid = nid or M.rawtip(npath)
  trace('at %s#%i -> %s#%i', cbr, cid, nbr, nid)
  local csnap  = M.snapshot(P, cbr,cid)
  local nsnap  = M.snapshot(P, nbr,nid)
  trace('at snaps %s -> %s', csnap, nsnap)

  local npaths = loadPaths(nsnap)

  local ok, cpPaths, rmPaths = true, {}, {}
  for _, path in ipairs(npaths) do
    local lpath, npath = P..path, nsnap..path
    if ix.pathEq(lpath, npath) then goto cont end -- local==next
    if ix.pathEq(lpath, csnap..path) then -- local didn't change
      if not ix.pathEq(csnap..path, npath) then -- next did change
        push(cpPaths, path)
      end
      goto cont
    end
    -- else local path changed
    if ix.pathEq(csnap..path, npath) then
      io.fmt:styled('meta',  sfmt('keeping changed %s', path), '\n')
    else
      io.fmt:styled('error', sfmt('path %s changed',    path), '\n')
      ok = false
    end
    ::cont::
  end
  -- look at paths in current but not next
  for path in io.lines(csnap..M.PVCPATHS) do
    if npaths[path]              then goto cont end
    if not ix.exists(P..path) then goto cont end -- already deleted
    if ix.pathEq(P..path, csnap..path) then push(rmPaths, path)
    else
      f:styled('error',
        sfmt('path %s changed but would be removed', path), '\n')
      ok = false
    end
    ::cont::
  end
  if not ok then error(sfmt(s[[

    ERROR: local changes (%s#%s) would be trampled by checkout %s#%s
    Solutions:
    * commit the current changes
    * revert the current changes
  ]], cbr,cid, nbr,nid)) end
  for _, path in ipairs(cpPaths) do
    trace('checkout cp: %s', path)
    ix.forceCp(nsnap..path, P..path)
  end
  for _, path in ipairs(rmPaths) do
    trace('checkout rm: %s', path)
    ix.rmRecursive(P..path)
  end
  M.rawat(P, nbr,nid)
  io.fmt:styled('notify', sfmt('pvc: at %s#%s', nbr,nid), '\n')
end

--- update paths file (path) with the added and removed items
M.pathsUpdate = function(P, add, rm)
  local pfile = pth.concat{P, M.PVCPATHS}
  local paths = assert(lines.load(pfile), pfile)
  if add then ds.extend(paths, add) end
  if rm and rm[1] then rm = ds.Set(rm) end
  local rmFn = rm and function(v1, v2) return rm[v2] or (v1 == v2) end
            or ds.eq
  ds.sortUnique(paths, nil, rmFn)
  push(paths, '')
  lines.dump(paths, pfile)
end

--- resolve a branch name. It can be one of: [+
--- * A directory with [$/] in it.
--- * [$branch] or [$branch#id]
--- * Special: at
--- ]
M.resolve = function(P, branch) --> br, id, bdir
  local br, id = M.parseBranch(branch)
  if not br then error('unknown branch: '..branch) end
  if br == 'local' then error('local not valid here') end
  if br == 'at'  then br, id = M.rawat(P) end
  return br, id, M.branchDir(P, br)
end

--- resolve and take snapshot, permits local
M.resolveSnap = function(P, branch) --> snap/, br, id, bdir
  if branch:find'/' then return branch end -- directory
  if branch == 'local' then return P end
  local br, id, bdir = M.resolve(P, branch)
  return M.snapshot(P, br, id or M.rawtip(bdir)), br, id, bdir
end

--- resolve two branches into their branch directories. Defaults:[+
--- * br1 = 'at'
--- * br2 = 'local'
--- ]
M.resolve2 = function(P, br1, br2) --> branch1/ branch2/
  return  M.resolveSnap(P, br1 or 'at'),
          M.resolveSnap(P, br2 or 'local')
end

M.diff = function(P, branch1, branch2) --> Diff
  return M.Diff:of(M.resolve2(P, branch1, branch2))
end

M.init = function(P, branch)
  P, branch = toDir(P), branch or 'main'
  local dot = P..'.pvc/';
  if ix.exists(dot) then error(dot..' already exists') end
  ix.mkTree(dot, {backup = {}}, true)
  initBranch(M.branchDir(P, branch), 0)
  pth.write(P..M.PVCPATHS, M.INIT_PVCPATHS)
  pth.write(P..'.pvcignore', '')
  M.rawat(P, branch, 0)
  io.fmt:styled('notice', 'initialized pvc repo '..dot, '\n')
end

--- Create a patch file from two branch arguments (see resolve2).
M.patch = function(P, br1, br2) --> string, s1, s2
  return M.Diff:of(M.resolve2(P, br1, br2)):patch()
end


local isPatchLike = function(line)
  return line:sub(1,3) == '---'
      or line:sub(1,3) == '+++'
      or line:sub(1,2) == '!!'
end
M.commit = function(P, desc) --> snap/, id
  assert(desc, 'commit must provide description')
  for _, line in ds.split(desc, '\n') do
    assert(not isPatchLike(line),
      "commit message cannot have any of the following"
    .." at the start of a line: +++, ---, !!")
  end

  local br, id = M.rawat(P)
  local bp, cid = M.branchDir(P, br), id+1
  trace('start commit %s/%s', br, cid)
  if id ~= M.rawtip(bp) then error(s[[
    ERROR: working id is not at tip. Solutions:
    * stash -> at tip -> unstash -> commit
    * prune: move or delete downstream changes.
  ]])end
  M.pathsUpdate(P) -- sort unique

  -- b=base c=change
  local bsnap = M.snapshot(P, br,id)
  local patchf = M.patchPath(bp, cid)
  local diff = M.Diff:of(bsnap, P)
  if not diff:hasDiff() then
    error('invalid commit: no differences detected')
  end
  if M.calcPatchDepth(cid) > M.depth(bp) then M.deepen(bp) end
  ix.forceWrite(patchf,
    sconcat('\n', desc, diff:patch()))
  local csnap = M.snapshot(P, br,cid)
  for path in io.lines(P..M.PVCPATHS) do
    T.pathEq(P..path, csnap..path)
  end
  M.rawtip(bp, cid); M.rawat(P, br, cid)
  io.fmt:styled('notify', sfmt('commited %s#%s to %s', br, cid, patchf), '\n')
  return csnap, cid
end

--- get the conventional brName, id for a branch,id pair
M.nameId = function(P, branch,id) --> br,id
  local br,bid; if not branch then br,bid = M.at(P)
  else                             br,bid = M.parseBranch(branch) end
  return br, id or bid or M.rawtip(M.branchDir(P, br))
end

M.branch = function(P, name, fbr,fid) --> bdir, id
  local fpath = M.branchDir(P, fbr)
  if not ix.exists(fpath) then error(fpath..' does not exist') end
  fid = fid or M.rawtip(fpath)
  local npath = M.branchDir(P, name)
  initBranch(npath, fid)
  pth.write(npath..'base', sfmt('%s#%s', fbr,fid))
  return npath, fid
end

local NOT_BRANCH = { backup = 1, at = 1}
local branchesRm = function(a, b) return NOT_BRANCH[a] end

--- get all branches
M.branches = function(P) --> list
  local entries = {}
  local d = P..'.pvc/'
  for e in ix.dir(d) do
    if not NOT_BRANCH[e] and ix.pathtype(d..e) == 'dir' then
      push(entries, pth.toNonDir(e))
    end
  end
  sort(entries)
  return entries
end

M.checkBranch = function(P, name, checks, dir)
  dir = dir or P..name
  local bbr,bid = M.getbase(dir, nil)
  local tip     = M.rawtip(dir)
  if tip <= bid then error(sfmt('tip %i <= baseid %i'..tip, bid)) end
  -- TODO: check that patch files exist, etc.

  if checks.base and not bbr then error(from..' does not have base') end
  if bbr then
    local bt = M.rawtip(M.branchDir(P, bbr))
    if bid > bt then error(sfmt(
      '%s base.id %s > %s tip of %i', from, bid, bbr, bt
    ))end
    -- TODO(sig): check signature
  end
  if checks.children then -- check that it has no children

  end
end

M.graft = function(P, name, from)
  local ndir = P..name
  if ix.exists(ndir) then error(ndir..' already exists') end
  M.checkBranch(P, name, {base=1}, from)
  ix.cpRecursive(from, ndir)
end

local FAILED_MERGE = [[
FAILED MERGE
    to: %s
  base: %s
change: %s
 ERROR: %s]]

M.merge = function(tdir, bdir, cdir) --!!>
  trace('pvc.merge to=%s base=%s change=%s', tdir, bdir, cdir)
  local paths, conflicts = {}, false
  mapPvcPaths(bdir, cdir, function(bpath, cpath)
    local to     = tdir..(cpath or bpath)
    local base   = bpath and (bdir..bpath) or nil
    local change = cpath and (cdir..cpath) or nil
    local ok, err = pu.merge(to, base, change)
    if not ok then
      io.fmt:styled('error', sfmt(
        FAILED_MERGE, to, base, change, err), '\n')
      conflicts = true
    end
  end)
  assert(not conflicts, 'failed to merge, fix conflicts and then re-run')
end

--- return a backup directory (uses the timestamp)
M.backupDir = function(P, name) --> string
  for _=1,10 do
    local b = sfmt('%s.pvc/backup/%s-%s/', P, name, M.backupId())
    if ix.exists(b) then ix.sleep(0.01) else return b end
  end
  error('could not find empty backup')
end

--- rebase the branch (current branch) to make it's baseid=id
M.rebase = function(P, branch, id) --> backup/dir/
  local cbr = branch

  --- process: repeatedly use merge on the (new) branch__rebase branch.
  --- the final result will be in to's last snapshot id
  local cpath = M.branchDir(P, cbr)
  local bbr, bid = M.getbase(cpath, cbr)
  M.at(P, bbr,bid) -- checkout base to ensure cleaner checkout at end

  if bbr == cbr then error('the base of '..cbr..' is itself') end
  if id == bid then return end
  local bdir = M.branchDir(P, bbr)
  local btip  = M.rawtip(bdir)
  if id > btip then error(id..' is > tip of '..btip) end

  local cdir, cid = M.branchDir(P, cbr), bid + 1
  local ctip       = M.rawtip(cdir)
  local tbr        = cbr..'__rebase'
  local tdir      = M.branchDir(P, tbr)
  local ttip       = id + M.rawtip(cdir) - bid

  local op = sfmt('rebase %s %s', cbr, bid)
  local tsnap; if ix.exists(tdir) then
    assert(ix.exists(tsnap))
    T.pathEq(tdir..'op', op)
    T.eq({bbr,bid}, M.getbase(tdir))
    cid   = toint(pth.read(tdir..'rebase'))
    tsnap = M.snapDir(tdir, ttip)
  else
    M.branch(P, tbr, bbr,id)
    pth.write(tdir..'op', op)
    tsnap = M.snapDir(tdir, ttip); ix.mkDirs(tsnap)
    cpPaths(M.snapshot(P, bbr,id), tsnap)
  end
  local tid = id + 1
  local tprev = M.snapshot(P, bbr,id) -- hard-code first prev

  while cid <= ctip do
    assert(tid <= ttip)
    local bsnap = M.snapshot(P, cbr,bid)
    pth.write(tdir..'rebase', tostring(cid))
    local desc = M.desc(M.patchPath(cdir, cid))
    M.merge(tsnap, bsnap, M.snapshot(P, cbr,cid))
    tprev = tprev or M.snapshot(P, tbr,tid-1)
    local tpatch = M.patchPath(tdir,tid)
    trace('writing patch %s', tpatch)
    ix.forceWrite(tpatch,
      concat(desc, '\n')..'\n'..M.Diff:of(tprev, tsnap):patch())
    tprev = nil
    bid, cid, tid = bid + 1, cid + 1, tid + 1
  end

  local backup = M.backupDir(P, cbr); ix.mkDirs(backup)
  ix.mv(cdir, backup)
  io.fmt:styled('notify',
    sfmt('pvc: rebase %s to %s#%s done. Backup at %s', cbr, bbr, id, backup),
    '\n')
  M.rawtip(tdir, ttip)
  ix.rm(tdir..'op'); ix.rm(tdir..'rebase')
  ix.mv(tdir, cdir)
  M.at(P, cbr,ttip)
  return backup
end

--- Grow [$to] by copying patches [$from]
M.grow = function(P, to, from) --!!>
  local fbr, fdir = assert(from, 'must set from'), M.branchDir(P, from)
  local ftip = M.rawtip(fdir)
  local bbr, bid = M.getbase(fdir)
  local tbr = to or M.rawat(P)
  if bbr ~= tbr then error(sfmt(
    'the base of %s is %s, not %s', from, bbr, tbr
  ))end
  local tdir = M.branchDir(P, tbr)
  local ttip = M.rawtip(tdir)
  if bid ~= ttip then error(sfmt(
    'rebase required (%s tip=%s, %s base id=%s)', tbr, ttip, bbr, bid
  ))end
  if ftip == bid then error(sfmt(
    "rebase not required: %s base is equal to it's tip (%s)", fbr, bid
  ))end
  M.at(P, tbr,ttip)
  if M.diff(P):hasDiff() then error'local changes detected' end
  -- TODO(sig): check signature
  for id=bid+1, M.rawtip(fdir) do
    local tpath = M.patchPath(tdir, id)
    assert(not ix.exists(tpath))
    local fpath = M.patchPath(fdir, id)
    info('copying: %s -> %s', fpath, tpath)
    ix.forceCp(fpath, tpath)
  end
  M.rawtip(tdir, ftip)
  local back = M.backupDir(P, fbr)
  io.fmt:styled('notify',
    sfmt('deleting %s (mv %s -> %s)', fbr, fdir, back), '\n')
  ix.mkDirs(pth.last(back)); ix.mv(fdir, back)
  io.fmt:styled('notify', sfmt('grew %s tip to %s', tbr, ftip), '\n')
  M.at(P, tbr,ftip)
end

--- return the description of ppath
M.desc = function(ppath, num) --> {string}
  local desc = {}
  for line in io.lines(ppath) do
    if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
      then break end
    push(desc, line); if num and #desc >= num then break end
  end
  return desc
end

--- squash num commits together before br#id.
M.squash = function(P, br, bot,top)
  trace('squash %s [%s %s]', br, bot,top)
  assert(br and bot and top, 'must set all args')
  assert(top > 0)
  if top - bot <= 0 then
    io.fmt:styled('error', sfmt('squashing ids [%s - %s] is a noop', bot, top), '\n')
    return
  end
  local bdir = M.branchDir(P, br)
  local tip, bbr, bid = M.rawtip(bdir), M.getbase(P, br)
  if bot <= bid then error(sfmt('bottom %i <= base id %s', top, bid)) end
  if top >  tip then error(sfmt('top %i > tip %i', top, tip)) end
  M.at(P, br,top)
  local back = M.backupDir(P, br..'-squash'); ix.mkDirs(back)
  local desc = {}
  local last = M.patchPath(bdir, tip)
  if not ix.exists(last) then error(last..' does not exist') end

  local patch = M.Diff:of(M.snapshot(P, br,bot-1), M.snapshot(P, br,top))
    :patch()
  -- move [bot,top] commits to backup/ and remove their .snap/ directories.
  for i=bot,top do
    local path = M.patchPath(bdir, i)
    ds.extend(desc, M.desc(path))
    local bpatch = back..i..'.p'
    ix.mv(path, bpatch)
    io.fmt:styled('notify', sfmt('mv %s %s', path, bpatch), '\n')
    ix.rmRecursive(M.snapDir(bdir, i))
  end
  -- write the squashed patch file
  local f = io.open(M.patchPath(bdir, bot), 'w')
  for _, line in ipairs(desc) do f:write(line, '\n') end
  f:write(patch); f:close()

  ix.rmRecursive(M.snapDir(bdir, bot)) -- TODO: remove this I think

  -- move the patch files above top down to be above squashed bot
  local bi = bot
  for i=top+1, tip do; bi = bi + 1
    ix.rmRecursive(M.snapDir(bdir, i))
    local botPat = M.patchPath(bdir, bi)
    local topPat = M.patchPath(bdir, i)
    io.fmt:styled('notify', sfmt('mv %s %s', topPat, botPat), '\n')
    ix.mv(topPat, botPat)
  end

  M.rawat(P, br,bot); M.rawtip(bdir,bi)
  io.fmt:styled('notify',
    sfmt('squashed [%s - %s] into %s. New tip=%i', bot, top, bot, bi), '\n')
end

local popdir = function(args)
  return pth.toDir(pk(args, 'dir') or pth.cwd())
end

local HELP = [=[[+
* sh usage:  [$pvc <cmd> [args]]
* lua usage: [$pvc{'cmd', ...}]
]

See README for details.
]=]
M.main = G.mod and G.mod'pvc.main' or setmetatable({}, {})

  --- [$help [cmd]]: get help
M.main.help = function(args) print(HELP) end

--- [$init dir]: initialize the [$dir] (default=CWD) for PVC.
M.main.init = function(args) --> nil
  M.init(popdir(args), args[1] or 'main')
end

--- [$diff branch1 branch2 --full]: get the difference (aka the patch) between
--- [$branch1] (default=[$at]) and [$branch2] (default=local). Each value can be
--- either a branch name or a directory which contains a [$.pvcpaths] file.
---
M.main.diff = function(args) --> Diff
  trace('diff%q', args)
  local P = popdir(args)
  local d = M.diff(P, args[1], args[2])
  d:format(io.fmt, args.full)
  if not args.full then
    for _, path in ipairs(untracked(P)) do
      io.user:styled('notify', path, '\n')
    end
  end
  io.fmt:write'\n'
  return d
end

--- [$commit]: add changes to the current branch as a patch and move [$at]
--- forward. The commit message can be written to the COMMIT file or be
--- specified after the [$--] argument, where multiple arguments are space
--- separated.
M.main.commit = function(args)
  local P = popdir(args)
  local desc = shim.popRaw(args)
  if desc then desc = concat(desc, ' ')
  else         desc = pth.read(P..'COMMIT') end
  M.commit(P, desc)
end

--- [$at [branch]]: if [$branch] is empty then return the active
--- [$branch#id].
---
--- If [$branch] is set then this sets the active [$branch#id], causing the
--- local directory to be updated (default id=tip).
--- ["git equivalent: [$checkout]]
M.main.at = function(args) --> string
  local D, branch = popdir(args), args[1]
  if branch then return M.at(D, M.parseBranch(branch)) end
  branch = sfmt('%s#%s', M.rawat(D))
  print(branch); return branch
end

--- [$tip [branch]]: get the highest branch#id for branch (default=at).
M.main.tip = function(args) --> string
  local P = popdir(args)
  local out = sfmt('%s#%s',
    M.rawtip(M.branchDir(P, args[1] or M.rawat(P))))
  print(out); return out
end

--- [$branch name [from]]: start a new branch of name [$name]. The optional
--- [$from] (default=[$at]) argument can specify a local [$branch#id] or an
--- (external) [$path/to/dir] to graft onto the pvc tree.
---
--- ["the [$from/dir] is commonly used by maintainers to accept patches from
--- contributors.
--- ]
M.main.branch = function(args)
  local D = popdir(args)
  local name = assert(args[1], 'must provide branch name')
  assert(not name:find'/', "branch name must not include '/'")

  local fbr,fid = args[2]
  if fbr and fbr:find'/' then return M.graft(D, name, fbr) end
  if fbr then fbr, fid = M.parseBranch(fbr)
  else        fbr, fid = M.rawat(D) end
  local bpath, id = M.branch(D, name, fbr,fid)
  M.at(D, name)
end

--- [$pvc show [branch#id] --num=10 --full]
---
--- If no branch is specified: show branches. [$full] also displays
--- the base and tip.
---
--- Else show branch#id and the previous [$num] commit messages.
--- With [$full] show the full commit message, else show only
--- the first line.
M.main.show = function(args)
  local D = popdir(args)
  local full = args.full
  if not args[1] then -- just show all branches
    for _, br in ipairs(M.branches(D)) do
      if full then
        local bdir = M.branchDir(D, br)
        local tip, base,bid = M.rawtip(bdir), M.getbase(bdir, nil)
        io.user:styled('notify', sfmt('%s\ttip=%s%s',
          br, tip, base and sfmt('\tbase=%s#%s', base,bid) or ''), '\n')
      else io.user:styled('notify', br, '\n') end
    end
    return
  end
  local br, id = M.parseBranch(args[1])
  if not br or br == 'at' then br, id = M.rawat(D) end

  local num, dir = toint(args.num or 10), M.branchDir(D, br)
  if not id then id = M.rawtip(dir) end
  local bbr, bid = M.getbase(dir)
  for i=id,id-num+1,-1 do
    if i <= 0 then break end
    if i == bid then
      br, dir = bbr, M.branchDir(D, bbr)
      bbr, bid = M.getbase(dir)
    end
    local ppath = M.patchPath(dir, i)
    local desc = M.desc(ppath, not full and 1 or nil)
    io.user:styled('notify', sfmt('%s#%s:', br,i), '')
    io.user:level(1)
    io.user:write(full and '\n' or ' ', concat(desc, '\n'))
    io.user:level(-1)
    io.user:write'\n'
  end
end

--- [$pvc desc branch [$path/to/new]]
--- get or set the description for a single branch id.
--- The default branch is [$at].
---
--- The new description can be passed via [$path/to/new] or
--- after [$--] (like commit).
M.main.desc = function(args)
  local P = popdir(args)
  local br, id, bdir = M.resolve(P,
    args[1] == '--' and 'at' or args[1] or 'at')
  local desc = shim.popRaw(args)
  if desc        then desc = concat(desc, ' ')
  elseif args[2] then desc = pth.read(args[2]) end
  local oldp = M.patchPath(bdir, id)
  local olddesc = concat(M.desc(oldp), '\n')
  if not desc then return print(olddesc) end
  -- Write new description
  local newp = sconcat('', bdir, tostring(id))
  local n = assert(io.open(newp, 'w'))
  n:write(desc, '\n')
  local o = assert(io.open(oldp, 'r'))
  for line in o:lines() do -- skip old desc
    if isPatchLike(line) then n:write(line, '\n'); break end
  end
  for line in o:lines() do n:write(line, '\n') end
  n:close(); o:close()
  local back = M.backupDir(P, sfmt('%s#%s', br, id)); ix.mkDirs(back)
  back = back..id..'.p'
  ix.mv(oldp, back)
  io.fmt:styled('notify', sfmt('moved %s -> %s', oldp, back), '\n')
  io.fmt:styled('notify', 'Old description (deleted):', '\n', olddesc, '\n')
  ix.mv(newp, oldp)
  io.fmt:styled('notify', 'updated desc of '..oldp, '\n')
end

--- [$pvc squash [branch#id endId]]
--- squash branch id -> endId (inclusive) into a single patch at [$id].
---
--- You can then edit the description by using [$pvc desc branch#id].
M.main.squash = function(args)
  trace('squash%q', args)
  local P = popdir(args)
  local br, bot,top
  if args[1] then
    br, bot = M.resolve(P, args[1])
    top     = toint(assert(args[2], 'must set endId'))
  else -- local commits
    br, bot = M.at(P); top = bot + 1
    M.commit(P, '')
  end
  M.squash(P, br, bot,top)
end

getmetatable(M.main).__call = function(_, args)
  trace('pvc%q', args)
  local cmd = table.remove(args, 1)
  local fn = rawget(M.main, cmd); if not fn then
    io.fmt:styled('error',
      cmd and (cmd..' is not recognized') or 'Must provide sub command', '\n')
    return M.main.help()
  end
  return fn(args)
end

--- [$rebase [branch [id]]]: change the base of branch to id.
--- (default branch=current, id=branch base's tip)
M.main.rebase = function(args) --> string
  local P = popdir(args)
  local br = args[1] ~= '' and args[1] or M.rawat(P)
  local base = M.getbase(M.branchDir(P,br))
  M.rebase(P, br, M.rawtip(M.branchDir(P, base)))
end

--- [$grow from --to=at]: grow [$to] (default=[$at]) using branch from.
---
--- ["In other version control systems this is called a
---   "fast forward merge"
--- ]
M.main.grow = function(args)
  local P = popdir(args)
  return M.grow(P, args.to, args[1])
end

--- [$prune branch [id]] delete branch by moving it to backup directory.
M.main.prune = function(args)
  local D = popdir(args)
  local br = assert(args[1], 'must specify branch')
  local bdir = M.branchDir(D, br)
  assert(ix.exists(bdir), bdir..' does not exist')
  local back = M.backupDir(D, br); ix.mkDirs(back)
  local id = args[2]
  if id then
    id = toint(id); local tip = M.rawtip(bdir)
    local d = M.depth(bdir)
    local undo = {}
    for i=id,tip do
      local from = M.patchPath(bdir,id, d)
      local to   = sfmt('%s%s.p', back, id)
      ix.mv(from, to)
      push(undo, sfmt('mv %s %s', to, from))
    end
    pth.write(back..'UNDO', table.concat(undo, '\n'))
    io.fmt:styled('notify', sfmt('pruned [%s -> %s]. Undo with %s',
      id, tip, back..'UNDO'))
  else
    ix.mv(bdir, back)
    io.fmt:styled('notify', sfmt('moved %s -> %s', bdir, back))
  end
end

--- [$export branch to/]: copy all patch files in the branch to [$to/].
---
--- ["the resulting directory is commonly sent to [$tar -zcvf branch.tar.gz path/]
---   and then [$branch.tar.gz] sent to a maintainer to be merged
--- ]
M.main.export = function(args) --> to
  local D = popdir(args)
  local br = assert(args[1], 'must specify branch')
  local to = pth.toDir(assert(args[2], 'must specify to/ directory'))
  if ix.exists(to) then error('to/ directory already exists: '..to) end

  local bdir = M.branchDir(D, br)
  local tip, bbr,bid = M.rawtip(bdir), M.getbase(bdir,nil)

  ix.mkDirs(to..'commit/')
  pth.write(bdir..'tip', tip)
  ix.cp(bdir..'commit/depth', to..'commit/depth')
  if bbr then pth.write(bdir..'base', sfmt('%s#%s', bbr,bid)) end
  -- Note: if base then first id isn't there
  for id=bbr and (bid+1) or bid, tip do
    ix.forceCp(M.patchPath(bdir,id, M.patchPath(to,id)))
  end
  io.fmt:styled('notify', sfmt('exported %s to %s', bdir, to))
  return to
end

--- [$snap [branch#id]] get the snapshot directory of branch#id
--- (default=at).
--- 
--- The snapshot contains a copy of files at that commit and
--- should not be modified.
M.main.snap = function(args) --> snap/
  local P = popdir(args)
  local br, id = M.resolve(P, args[1] or 'at')
  local snap = M.snapshot(P, br, id)
  io.stdout:write(snap, '\n')
  return pth.nice(snap)
end

getmetatable(M).__call = getmetatable(M.main).__call

return M

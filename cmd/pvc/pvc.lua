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
  local paths = lines.load(P..M.PVCPATHS)
  push(paths, '.pvcpaths')
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
  local paths1, paths2 = {}, {}
  for p in io.lines(dir1..M.PVCPATHS) do paths1[p] = 1 end
  for p in io.lines(dir2..M.PVCPATHS) do paths2[p] = 1 end
  for p1 in pairs(paths1) do fn(p1, paths2[p1] and p1 or nil) end
  for p2 in pairs(paths2) do
    if not paths1[p2] then fn(nil, p2) end
  end
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
M.branchPath = function(pdir, branch, dot)
  assert(branch, 'branch is nil')
  assert(not M.RESERVED_NAMES[branch], 'branch name is reserved')
  return pth.concat{pdir, dot or '.pvc', branch, '/'}
end

M.getbase = function(bpath, br) --> br, id
  bpath = bpath..'base'
  if ix.exists(bpath) then return M.parseBranch(pth.read(bpath))
  else return br, 0 end
end
M.rawtip = function(bpath, id)
  if id then pth.write(toDir(bpath)..'tip', tostring(id))
  else return readInt(toDir(bpath)..'tip') end
end
M.depth = function(bpath) return readInt(toDir(bpath)..'patch/depth') end

M.patchPath = function(bpath, id, last, depth) --> string?
  depth = depth or M.depth(bpath)
  if M.calcPatchDepth(id) > depth then return end
  local dirstr = tostring(id):sub(1,-3)
  dirstr = srep('0', depth - #dirstr)..dirstr -- zero padded
  local path = {bpath, 'patch'}; for i=1,#dirstr,2 do
    push(path, dirstr:sub(i,i+1)) -- i.e. 00/12.p
  end
  push(path, tostring(id)..(last or ''))
  return pconcat(path)
end

--- Get the snap/ path regardless of whether it exists
M.snapDir = function(bpath, id) --> string?
  return M.patchPath(bpath, id, '.snap/')
end

local function initBranch(bpath, id)
  assert(id >= 0)
  assertf(not ix.exists(bpath), '%s already exists', bpath)
  local depth = M.calcPatchDepth(id + 1000)
  trace('initbranch %s', bpath)
  ix.mkTree(bpath, {
    tip=tostring(id), patch = {depth=tostring(depth)},
  }, true)
  if id ~= 0 then return bpath end
  local ppath = M.patchPath(bpath, id, '', depth)
  ix.forceWrite(ppath..'.snap/.pvcpaths', M.INIT_PVCPATHS)
  ix.forceWrite(ppath..'.snap/PVC_DONE', '')
end

--- Snapshot the branch#id by applying patches.
--- Return the snapshot directory
M.snapshot = function(pdir, br,id) --> .../id.snap/
  trace('snapshot %s#%s', br,id)
  -- f=from, t=to
  local bpath = M.branchPath(pdir, br)
  local snap = M.snapDir(bpath, id)
  if ix.exists(snap) then return snap, id end
  local bbr,bid = M.getbase(bpath, br)
  if id == bid then return M.snapshot(pdir, bbr,bid) end
  trace('findSnap %s id=%s with base %s#%s', bpath, id, bbr,bid)

  local tip      = M.rawtip(bpath)
  local fsnap, fid -- find the snap/id to patch from
  local idl, idr = id-1, id+1
  while (bid <= idl) or (idr <= tip) do
    snap = M.patchPath(bpath, idl, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = M.snapDir(bpath,idl), idl; break
    end
    if bid == idl then
      fsnap, fid = M.snapshot(pdir, bbr,bid), idl; break
    end
    snap = M.patchPath(bpath, idr, '.snap/PVC_DONE')
    if ix.exists(snap) then
      fsnap, fid = M.snapDir(bpath,idr), idr; break
    end
    idl, idr = idl-1, idr+1
  end
  if not fsnap then error(bpath..' does not have snapshot '..id) end
  local tsnap = M.snapDir(bpath, id)
  trace('creating snapshot %s from %s', tsnap, fsnap)
  if ix.exists(tsnap) then ix.rmRecursive(tsnap) end
  ix.mkDir(tsnap)
  cpPaths(fsnap, tsnap)
  local patch = (fid <= id) and pu.patch or pu.rpatch
  local inc   = (fid <= id) and 1       or -1
  fid = fid + inc
  while true do
    local ppath = M.patchPath(bpath, fid, '.p')
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
M.deepen = function(bpath)
  local depth, pp, zz = M.depth(bpath), bpath..'patch/', bpath..'00/'
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
M.rawat = function(pdir, branch, id)
  local apath = pth.concat{pdir, '.pvc/at'}
  if branch then pth.write(apath, sfmt('%s#%s', branch, id))
  else    return M.parseBranch(pth.read(apath)) end
end

--- get or set where the working id is at.
M.at = function(pdir, nbr,nid) --!!> branch?, id?
  -- c=current, n=next
  local cbr, cid = M.rawat(pdir); if not nbr then return cbr, cid end
  local npath = M.branchPath(pdir, nbr)

  nid = nid or M.rawtip(npath)
  trace('at %s#%i -> %s#%i', cbr, cid, nbr, nid)
  local csnap  = M.snapshot(pdir, cbr,cid)
  local nsnap  = M.snapshot(pdir, nbr,nid)
  trace('at snaps %s -> %s', csnap, nsnap)

  local npaths = loadLineSet(nsnap..M.PVCPATHS)

  local ok, cpPaths, rmPaths = true, {}, {}
  for path in pairs(npaths) do
    if ix.pathEq(pdir..path, nsnap..path) then goto cont end -- local==next
    if ix.pathEq(pdir..path, csnap..path) then -- local didn't change
      if not ix.pathEq(csnap..path, nsnap..path) then -- next did change
        push(cpPaths, path)
      end
      goto cont
    end
    -- else local path changed
    if ix.pathEq(csnap..path, nsnap..path) then
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
    if not ix.exists(pdir..path) then goto cont end -- already deleted
    if ix.pathEq(pdir..path, csnap..path) then push(rmPaths, path)
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
    ix.forceCp(nsnap..path, pdir..path)
  end
  for _, path in ipairs(rmPaths) do
    trace('checkout rm: %s', path)
    ix.rmRecursive(pdir..path)
  end
  M.rawat(pdir, nbr,nid)
  io.fmt:styled('notify', sfmt('pvc: at %s#%s', nbr,nid), '\n')
end

--- update paths file (path) with the added and removed items
M.pathsUpdate = function(pdir, add, rm)
  local pfile = pth.concat{pdir, M.PVCPATHS}
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
--- * Special: local, at
--- ]
M.resolve = function(pdir, branch) --> directory/
  if branch:find'/' then return branch end -- directory
  local br, id = M.parseBranch(branch)
  if not br then error('unknown branch: '..branch) end
  if br == 'local' then return pdir end
  if br == 'at'  then br, id = M.rawat(pdir) end
  local bpath = M.branchPath(pdir, br)
  return M.snapshot(pdir, br, id or M.rawtip(bpath))
end

--- resolve two branches into their branch directories. Defaults:[+
--- * br1 = 'at'
--- * br2 = 'local'
--- ]
M.resolve2 = function(pdir, br1, br2) --> branch1/ branch2/
  return  M.resolve(pdir, br1 or 'at'),
          M.resolve(pdir, br2 or 'local')
end

M.diff = function(pdir, branch1, branch2) --> Diff
  return M.Diff:of(M.resolve2(pdir, branch1, branch2))
end

M.init = function(pdir, branch)
  pdir, branch = toDir(pdir), branch or 'main'
  local dot = pdir..'.pvc/';
  if ix.exists(dot) then error(dot..' already exists') end
  ix.mkTree(dot, {backup = {}}, true)
  initBranch(M.branchPath(pdir, branch), 0)
  pth.write(pdir..M.PVCPATHS, M.INIT_PVCPATHS)
  pth.write(pdir..'.pvcignore', '')
  M.rawat(pdir, branch, 0)
  io.fmt:styled('notice', 'initialized pvc repo '..dot, '\n')
end

--- Create a patch file from two branch arguments (see resolve2).
M.patch = function(pdir, br1, br2) --> string, s1, s2
  return M.Diff:of(M.resolve2(pdir, br1, br2)):patch()
end

M.commit = function(pdir, desc) --> snap/, id
  assert(desc, 'commit must provide description')
  if   desc:sub(1,3) == '---' or desc:find('\n---', 1, true)
    or desc:sub(1,3) == '+++' or desc:find('\n+++', 1, true)
    or desc:sub(1,2) == '!!'  or desc:find('\n!!',  1, true)
    then error(
      "commit message cannot have any of the following"
    .." at the start of a line: +++, ---, !!"
  )end

  local br, id = M.rawat(pdir)
  local bp, cid = M.branchPath(pdir, br), id+1
  trace('start commit %s/%s', br, cid)
  if id ~= M.rawtip(bp) then error(s[[
    ERROR: working id is not at tip. Solutions:
    * stash -> at tip -> unstash -> commit
    * prune: move or delete downstream changes.
  ]])end
  M.pathsUpdate(pdir) -- sort unique

  -- b=base c=change
  if M.calcPatchDepth(cid) > M.depth(bp) then M.deepen(bp) end
  local bsnap = M.snapshot(pdir, br,id)
  -- TODO(commit): add description
  local patchf = M.patchPath(bp, cid, '.p')
  ix.forceWrite(patchf,
    sconcat('\n', desc, M.Diff:of(bsnap, pdir):patch()))
  local csnap = M.snapshot(pdir, br,cid)
  for path in io.lines(pdir..M.PVCPATHS) do
    T.pathEq(pdir..path, csnap..path)
  end
  M.rawtip(bp, cid); M.rawat(pdir, br, cid)
  io.fmt:styled('notify', sfmt('commited %s#%s to %s', br, cid, patchf), '\n')
  return csnap, cid
end

--- get the conventional brName, id for a branch,id pair
M.nameId = function(pdir, branch,id) --> br,id
  local br,bid; if not branch then br,bid = M.at(pdir)
  else                             br,bid = M.parseBranch(branch) end
  return br, id or bid or M.rawtip(M.branchPath(pdir, br))
end

M.branch = function(pdir, name, fbr,fid) --> bpath, id
  local fpath = M.branchPath(pdir, fbr)
  if not ix.exists(fpath) then error(fpath..' does not exist') end
  fid = fid or M.rawtip(fpath)
  local npath = M.branchPath(pdir, name)
  initBranch(npath, fid)
  pth.write(npath..'base', sfmt('%s#%s', fbr,fid))
  return npath, fid
end

local NOT_BRANCH = { backup = 1, at = 1}
local branchesRm = function(a, b) return NOT_BRANCH[a] end

--- get all branches
M.branches = function(pdir) --> list
  local entries = {}
  local d = pdir..'.pvc/'
  for e in ix.dir(d) do
    if not NOT_BRANCH[e] and ix.pathtype(d..e) == 'dir' then
      push(entries, pth.toNonDir(e))
    end
  end
  sort(entries)
  return entries
end

M.checkBranch = function(pdir, name, checks, dir)
  dir = dir or pdir..name
  local bbr,bid = M.getbase(dir, nil)
  local tip     = M.rawtip(dir)
  if tip <= bid then error(sfmt('tip %i <= baseid %i'..tip, bid)) end
  -- TODO: check that patch files exist, etc.

  if checks.base and not bbr then error(from..' does not have base') end
  if bbr then
    local bt = M.rawtip(M.branchPath(pdir, bbr))
    if bid > bt then error(sfmt(
      '%s base.id %s > %s tip of %i', from, bid, bbr, bt
    ))end
    -- TODO(sig): check signature
  end
  if checks.children then -- check that it has no children

  end
end

M.graft = function(pdir, name, from)
  local ndir = pdir..name
  if ix.exists(ndir) then error(ndir..' already exists') end
  M.checkBranch(pdir, name, {base=1}, from)
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
    print('!! backupDir', b)
    if ix.exists(b) then ix.sleep(0.01) else return b end
  end
  error('could not find empty backup')
end

--- rebase the branch (current branch) to make it's baseid=id
M.rebase = function(pdir, branch, id)
  local cbr = branch

  --- process: repeatedly use merge on the (new) branch__rebase branch.
  --- the final result will be in to's last snapshot id
  local cpath = M.branchPath(pdir, cbr)
  local bbr, bid = M.getbase(cpath, cbr)
  M.at(pdir, bbr,bid) -- checkout base to ensure cleaner checkout at end

  if bbr == cbr then error('the base of '..cbr..' is itself') end
  if id == bid then return end
  local bpath = M.branchPath(pdir, bbr)
  local btip  = M.rawtip(bpath)
  if id > btip then error(id..' is > tip of '..btip) end

  local cpath, cid = M.branchPath(pdir, cbr), bid + 1
  local ctip       = M.rawtip(cpath)
  local tbr        = cbr..'__rebase'
  local tpath      = M.branchPath(pdir, tbr)
  local ttip       = id + M.rawtip(cpath) - bid

  local op = sfmt('rebase %s %s', cbr, bid)
  local tsnap; if ix.exists(tpath) then
    assert(ix.exists(tsnap))
    T.pathEq(tpath..'op', op)
    T.eq({bbr,bid}, M.getbase(tpath))
    cid   = toint(pth.read(tpath..'rebase'))
    tsnap = M.snapDir(tpath, ttip)
  else
    M.branch(pdir, tbr, bbr,id)
    pth.write(tpath..'op', op)
    tsnap = M.snapDir(tpath, ttip); ix.mkDirs(tsnap)
    cpPaths(M.snapshot(pdir, bbr,id), tsnap)
  end
  local tid = id + 1
  local tprev = M.snapshot(pdir, bbr,id) -- hard-code first prev

  while cid <= ctip do
    assert(tid <= ttip)
    local bsnap = M.snapshot(pdir, cbr,bid)
    pth.write(tpath..'rebase', tostring(cid))
    M.merge(tsnap, bsnap, M.snapshot(pdir, cbr,cid))
    -- TODO(commit): preserve description
    tprev = tprev or M.snapshot(pdir, tbr,tid-1)
    local tpatch = M.patchPath(tpath,tid, '.p')
    trace('writing patch %s', tpatch)
    ix.forceWrite(tpatch, M.Diff:of(tprev, tsnap):patch())
    tprev = nil
    bid, cid, tid = bid + 1, cid + 1, tid + 1
  end

  local backup = M.backupDir(pdir, cbr); ix.mkDir(backup)
  ix.mv(cpath, backup)
  io.fmt:styled('notify',
    sfmt('pvc: rebase %s to %s#%s done. Backup at %s', cbr, bbr, id, backup),
    '\n')
  M.rawtip(tpath, ttip)
  ix.rm(tpath..'op'); ix.rm(tpath..'rebase')
  ix.mv(tpath, cpath)
  M.at(pdir, cbr,ttip)
end

--- Grow [$to] by copying patches [$from]
M.grow = function(P, to, from) --!!>
  local fbr, fdir = assert(from, 'must set from'), M.branchPath(P, from)
  local ftip = M.rawtip(fdir)
  local bbr, bid = M.getbase(fdir)
  local tbr = to or M.rawat(P)
  if bbr ~= tbr then error(sfmt(
    'the base of %s is %s, not %s', from, bbr, tbr
  ))end
  local tdir = M.branchPath(P, tbr)
  local ttip = M.rawtip(tdir)
  if bid ~= ttip then error(sfmt(
    'rebase required (%s tip=%s, %s base id=%s)', tbr, ttip, bbr, bid
  ))end
  if ftip == bid then error(sfmt(
    "rebase not required: %s base is equal to it's tip (%s)", fbr, bid
  ))end
  -- TODO(sig): check signature
  for id=bid+1, M.rawtip(fdir) do
    local tpath = M.patchPath(tdir, id, '.p')
    assert(not ix.exists(tpath))
    local fpath = M.patchPath(fdir, id, '.p')
    info('copying: %s -> %s', fpath, tpath)
    ix.forceCp(fpath, tpath)
  end
  M.rawtip(tdir, ftip)
  local back = M.backupDir(P, fbr)
  assert(not ix.exists(back), 'WHAT: '..back)
  io.fmt:styled('notify',
    sfmt('deleting %s (mv %s -> %s)', fbr, fdir, back), '\n')
  ix.mv(fdir, back)
  io.fmt:styled('notify', sfmt('grew %s tip to %s', tbr, ftip), '\n')
  if not to then M.at(to, ftip) end
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

--- [$tip [branch]]: get the highest branch#id for branch (default=at).
M.main.tip = function(args) --> string
  local P = popdir(args)
  local out = sfmt('%s#%s',
    M.rawtip(M.branchPath(P, args[1] or M.rawat(P))))
  print(out); return out
end

--- [$grow from --to=at]: grow [$to] (default=[$at]) using branch from.
M.main.grow = function(args)
  local P = popdir(args)
  return M.grow(P, args.to, args[1])
end

--- [$rebase [branch [id]]]: change the base of branch to id.
--- (default branch=current, id=branch base's tip)
M.main.rebase = function(args) --> string
  local P = popdir(args)
  local br = args[1] ~= '' and args[1] or M.rawat(P)
  local base = M.getbase(M.branchPath(P,br))
  M.rebase(br, M.rawtip(M.branchpath(P, base)))
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
--- specified after the [$--] argument, where multiple arguments are newline
--- separated.
M.main.commit = function(args)
  local P = popdir(args)
  local desc = shim.popRaw(args)
  if desc then desc = concat(desc, '\n')
  else         desc = pth.read(P..'COMMIT') end
  M.commit(P, desc)
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

  local bdir = M.branchPath(D, br)
  local tip, bbr,bid = M.rawtip(bdir), M.getbase(bdir,nil)

  ix.mkDirs(to..'patch/')
  pth.write(bdir..'tip', tip)
  ix.cp(bdir..'patch/depth', to..'patch/depth')
  if bbr then pth.write(bdir..'base', sfmt('%s#%s', bbr,bid)) end
  -- Note: if base then first id isn't there
  for id=bbr and (bid+1) or bid, tip do
    ix.forceCp(M.patchPath(bdir,id, '.p', M.patchPath(to,id, '.p')))
  end
  io.fmt:styled('notify', sfmt('exported %s to %s', bdir, to))
  return to
end

--- [$prune branch [id]] delete branch by moving it to backup directory.
M.main.prune = function(args)
  local D = popdir(args)
  local br = assert(args[1], 'must specify branch')
  local bdir = M.branchPath(D, br)
  assert(ix.exists(bdir), bdir..' does not exist')
  local back = M.createBackup(D, br)
  local id = args[2]
  if id then
    id = toint(id); local tip = M.rawtip(bdir)
    local d = M.depth(bdir)
    local undo = {}
    for i=id,tip do
      local from = M.patchPath(bdir,id, '.p', d)
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

M.main.show = function(args)
  local D = popdir(args)
  local full = args.full
  if not args[1] then -- just show all branches
    for _, br in ipairs(M.branches(D)) do
      if full then
        local bdir = M.branchPath(D, br)
        local tip, base,bid = M.rawtip(bdir), M.getbase(bdir, nil)
        io.user:styled('notify', sfmt('%s\ttip=%s%s',
          br, tip, base and sfmt('\tbase=%s#%s', base,bid) or ''), '\n')
      else io.user:styled('notify', br, '\n') end
    end
    return
  end
  local br, id = M.parseBranch(args[1])
  if not br or br == 'at' then br, id = M.rawat(D) end

  local num, dir = toint(args.num or 10), M.branchPath(D, br)
  if not id then id = M.rawtip(dir) end
  local bbr, bid = M.getbase(dir)
  for i=id,id-num+1,-1 do
    if i <= 0 then break end
    if i == bid then
      br, dir = bbr, M.branchPath(D, bbr)
      bbr, bid = M.getbase(dir)
    end
    local ppath = M.patchPath(dir, i, '.p')
    local desc = {}
    for line in io.lines(ppath) do
      if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
        then break end
      push(desc, line); if not full then break end
    end
    io.user:styled('notify', sfmt('%s#%s:', br,i), '')
    io.user:level(1)
    io.user:write(full and '\n' or ' ', concat(desc, '\n'))
    io.user:level(-1)
    io.user:write'\n'
  end
end

getmetatable(M.main).__call = function(_, args)
  trace('pvc%q', args)
  local cmd = table.remove(args, 1)
  local fn = rawget(M.main, cmd); if not fn then
    io.fmt:styled('error', cmd..' is not recognized', '\n')
    M.main.help()
  end
  return fn(args)
end

getmetatable(M).__call = getmetatable(M.main).__call

return M

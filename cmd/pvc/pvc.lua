local G = G or _G
local M = G.mod and mod'pvc2' or setmetatable({}, {})
MAIN = G.MAIN or M

local shim = require'shim'
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
local toDir, pconcat = pth.toDir, pth.concat

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
M.backupId = function() return toint(ix.epoch().s) end

--- reserved branch names
M.RESERVED_NAMES = { ['local']=1, at=1, tip=1, }

-----------------------------------
-- Utilities

--- get a set of the lines in a file
local loadLineSet = function(path) --> set
  local s = {}; for l in io.lines(path) do s[l] = true end; return s
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
  print('!! mapPaths dir1, dir2', dir1, dir2)
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
  print('!! getting diff:', d1, d2)
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

M.Diff.format = function(d, fmt, full)
  local function s(...) return fmt:styled(...) end
  if full then
    for _, line in ds.split(d:patch(), '\n') do
      if     line:sub(1,1) == '-' then s('base',   line, '\n')
      elseif line:sub(1,1) == '+' then s('change', line, '\n')
      else fmt:write(line, '\n') end
    end
  else
    if (#d.changed == 0) and (#d.deleted == 0) and (#d.created == 0) then
      return s('bold', 'No Difference')
    end
    s('bold', 'Diff:', ' ', d.dir1, ' --> ', d.dir2, '\n')
    for _,path in ipairs(d.deleted) do s('base',   '-'..path, '\n') end
    for _,path in ipairs(d.created) do s('change', '-'..path, '\n') end
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

M.getbase = function(bpath, br) --> br?, id
  bpath = bpath..'base'
  if ix.exists(bpath) then return M.parseBranch(pth.read(bpath))
  else return nil, 0 end
end
M.rawtip = function(bpath, id)
  if id then pth.write(toDir(bpath)..'tip', tostring(id))
  else return readInt(toDir(bpath)..'tip') end
end
M.depth = function(bpath) return readInt(toDir(bpath)..'patch/depth') end

M.patchPath = function(bpath, id, last, depth) --> string?
  print('!! patchPath', bpath, id, last, depth)
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
M.atraw = function(pdir, branch, id)
  local apath = pth.concat{pdir, '.pvc/at'}
  if branch then pth.write(apath, sfmt('%s#%s', branch, id))
  else    return M.parseBranch(pth.read(apath)) end
end

--- get or set where the working id is at.
M.at = function(pdir, nbr,nid) --!!> branch?, id?
  -- c=current, n=next
  local cbr, cid = M.atraw(pdir); if not nbr then return cbr, cid end
  local npath = M.branchPath(pdir, nbr)

  nid = nid or M.rawtip(npath)
  trace('at %s#%i -> %s#%i', cbr, cid, nbr, nid)
  local csnap  = M.snapshot(pdir, cbr,cid)
  local nsnap  = M.snapshot(pdir, nbr,nid)
  trace('at snaps %s -> %s', csnap, nsnap)

  print('!! at snaps', csnap, nsnap)
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
  M.atraw(pdir, nbr,nid)
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
  trace('!! before sort %q', rmFn, paths)
  ds.sortUnique(paths, nil, rmFn)
  trace('!! after sort', paths)
  push(paths, '')
  lines.dump(paths, pfile)
end

--- resolve a branch name. It can be one of: [+
--- * A directory with [$/] in it.
--- * [$branch] or [$branch#id]
--- * Special: local, at
--- ]
M.resolve = function(pdir, branch) --> directory/
  print('!! resolve', pdir, branch)
  if branch:find'/' then return branch end -- directory
  local br, id = M.parseBranch(branch)
  if not br then error('unknown branch: '..branch) end
  if br == 'local' then return pdir end
  if br == 'at'  then br, id = M.atraw(pdir) end
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
  M.atraw(pdir, branch, 0)
  info('initialized pvc repo: %s', pdir)
end

--- Create a patch file from two branch arguments (see resolve2).
M.patch = function(pdir, br1, br2) --> string, s1, s2
  return M.Diff:of(M.resolve2(pdir, br1, br2)):patch()
end

M.commit = function(pdir) --> snap/, id
  local br, id = M.atraw(pdir)
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
  ix.forceWrite(M.patchPath(bp, cid, '.p'),
                M.Diff:of(bsnap, pdir):patch())
  local csnap = M.snapshot(pdir, br,cid)
  for path in io.lines(pdir..M.PVCPATHS) do
    T.pathEq(pdir..path, csnap..path)
  end
  M.rawtip(bp, cid); M.atraw(pdir, br, cid)
  info('commited %s#%s', br, cid)
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
  -- ix.forceCp(M.patchPath(fpath, fid, '.p'), M.patchPath(npath, fid, '.p'))
  pth.write(npath..'base', sfmt('%s#%s', fbr,fid))
  return npath, fid
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
  local btip = M.rawtip(bpath)
  if id > btip then error(id..' is > tip of '..btip) end

  local cpath = M.branchPath(pdir, cbr)
  local tbr = cbr..'__rebase'
  local tpath = M.branchPath(pdir, tbr)
  local ttip = id + M.rawtip(cpath) - bid
  local tsnap

  local op = sfmt('rebase %s %s', cbr, bid)
  if ix.exists(tpath) then
    T.pathEq(tpath..'op', op)
    bid = select(2, M.getbase(tpath))
    tsnap = M.snapDir(tpath, ttip)
    assert(ix.exists(tsnap))
  else
    local tpath = M.branch(pdir, tbr, bbr,id)
    tsnap = M.snapDir(tpath, ttip); ix.mkDirs(tsnap)
    cpPaths(M.snapshot(pdir, bbr,id), tsnap)
    pth.write(tpath..'op', op)
  end
  local bsnap = M.snapshot(pdir, bbr, bid)
  local csnap = M.snapshot(pdir, cbr, bid + 1)
  local tid = id + 1
  -- the first base we must hard-code tsnap because
  -- snapshot will freak out that there aren't any .p files.
  local tbase = M.snapshot(pdir, bbr,id)

  while bid < id do
    assert(tid <= ttip)
    pth.write(tpath..'base', sfmt('%s#%s', bbr, bid+1))
    M.merge(tsnap, bsnap, csnap)
    -- TODO(commit): preserve description
    tbase = tbase or M.snapshot(pdir, tbr,tid-1)
    pth.write(
      M.patchPath(tpath,tid, '.p'),
      M.Diff:of(tbase, tsnap):patch())
    tbase = nil
    bid, tid = bid + 1, tid + 1
    bsnap = M.snapshot(pdir, bbr,bid)
    csnap = M.snapshot(pdir, cbr,bid)
  end

  local backup = sfmt('%s.pvc/backup/%s-%s/', pdir, cbr, M.backupId())
  ix.mv(cpath, backup)
  io.fmt:styled('notify',
    sfmt('pvc: rebase %s to %s#%s done. Backup at %s', cbr, bbr, id, backup),
    '\n')
  ix.mv(tpath, cpath); ix.rm(cpath..'op')
  M.at(pdir, cbr,ttip)
end

M.main = function(args) error'todo' end

return M

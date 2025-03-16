initial squash commit
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -418 +418 @@
---- * Special: local, at
+--- * Special: at
@@ -420,2 +420 @@
-M.resolve = function(pdir, branch) --> directory/
-  if branch:find'/' then return branch end -- directory
+M.resolve = function(P, branch) --> br, id, bpath
@@ -424,4 +423,11 @@
-  if br == 'local' then return pdir end
-  if br == 'at'  then br, id = M.rawat(pdir) end
-  local bpath = M.branchPath(pdir, br)
-  return M.snapshot(pdir, br, id or M.rawtip(bpath))
+  if br == 'local' then error('local not valid here') end
+  if br == 'at'  then br, id = M.rawat(P) end
+  return br, id, M.branchPath(P, br)
+end
+
+--- resolve and take snapshot, permits local
+M.resolveSnap = function(pdir, branch) --> snap/, br, id, bpath
+  if branch:find'/' then return branch end -- directory
+  if branch == 'local' then return pdir end
+  local br, id, bdir = M.resolve(pdir, branch)
+  return M.snapshot(pdir, br, id or M.rawtip(bdir)), br, id, bdir
@@ -435,2 +441,2 @@
-  return  M.resolve(pdir, br1 or 'at'),
-          M.resolve(pdir, br2 or 'local')
+  return  M.resolveSnap(pdir, br1 or 'at'),
+          M.resolveSnap(pdir, br2 or 'local')
@@ -459,0 +466,6 @@
+
+local isPatchLike = function(line)
+  return line:sub(1,3) == '---'
+      or line:sub(1,3) == '+++'
+      or line:sub(1,2) == '!!'
+end
@@ -462,4 +474,2 @@
-  if   desc:sub(1,3) == '---' or desc:find('\n---', 1, true)
-    or desc:sub(1,3) == '+++' or desc:find('\n+++', 1, true)
-    or desc:sub(1,2) == '!!'  or desc:find('\n!!',  1, true)
-    then error(
+  for _, line in ds.split(desc, '\n') do
+    assert(not isPatchLike(line),
@@ -467,2 +477,2 @@
-    .." at the start of a line: +++, ---, !!"
-  )end
+    .." at the start of a line: +++, ---, !!")
+  end
@@ -669,0 +680,2 @@
+  M.at(P, tbr,ttip)
+  if M.diff(P):hasDiff() then error'local changes detected' end
@@ -680 +691,0 @@
-  assert(not ix.exists(back), 'WHAT: '..back)
@@ -685 +696,60 @@
-  if not to then M.at(to, ftip) end
+  M.at(P, to,ftip)
+end
+
+--- return the description of ppath
+M.desc = function(ppath, num) --> {string}
+  local desc = {}
+  for line in io.lines(ppath) do
+    if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
+      then break end
+    push(desc, line); if num and #desc >= num then break end
+  end
+  return desc
+end
+
+--- squash num commits together before br#id.
+M.squash = function(P, br,id, num)
+  trace('squash %s %s %s', br, id, num)
+  assert(br and id and num, 'must set all args')
+  assert(id > 0)
+  assert(num > 1, 'num must be >= 2')
+  local bdir = M.branchPath(P, br)
+  local tip, bbr, bid = M.rawtip(bdir), M.getbase(P, br)
+  local bot = id - num + 1
+  if bot <= bid then error(sfmt('bottom %i <= base id %s', id, bid)) end
+  if id  >  tip then error(sfmt('id %i > tip %i', id, tip)) end
+  M.at(P, br,id)
+  local back = M.backupDir(P, br..'-squash'); ix.mkDir(back)
+  local desc = {}
+  local last = M.patchPath(bdir, tip, '.p')
+  if not ix.exists(last) then error(last..' does not exist') end
+
+  local patch = M.Diff:of(M.snapshot(P, br,bot-1), M.snapshot(P, br,id))
+    :patch()
+  for i=bot,id do
+    local path = M.patchPath(bdir, i, '.p')
+    ds.extend(desc, M.desc(path))
+    local bpatch = back..i..'.p'
+    ix.mv(path, bpatch)
+    io.fmt:styled('notify', sfmt('mv %s %s', path, bpatch), '\n')
+    ix.rmRecursive(M.snapDir(bdir, i))
+  end
+  local f = io.open(M.patchPath(bdir, id, '.p'), 'w')
+  for _, line in ipairs(desc) do f:write(line, '\n') end
+  f:write(patch); f:flush(); f:close()
+
+  ix.rmRecursive(M.snapDir(bdir, bot))
+  local bi = bot + 1
+  for i=id+1, tip do
+    ix.rmRecursive(M.snapDir(bdir, i))
+    local bpat = M.patchPath(bdir, bi, '.p')
+    local tpat = M.patchPath(bdir, i, '.p')
+    io.fmt:styled('notify', sfmt('mv %s %s', tpat, bpat), '\n')
+    ix.mv(tpat, bpat)
+    bi = bi + 1
+  end
+  local ppath = M.patchPath(bdir, bot, '.p')
+  pth.write(ppath, patch)
+  M.rawat(P, br,bot)
+  io.fmt:styled('notify',
+    sfmt('squashed [%s - %s] into %s', bot, id, ppath), '\n')
@@ -857 +927 @@
-  local back = M.createBackup(D, br)
+  local back = M.backupDir(D, br); ix.mkDir(back)
@@ -905,6 +975 @@
-    local desc = {}
-    for line in io.lines(ppath) do
-      if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
-        then break end
-      push(desc, line); if not full then break end
-    end
+    local desc = M.desc(ppath, not full and 1 or nil)
@@ -916,0 +982,41 @@
+end
+
+
+--- [$pvc desc branch [$path/to/new]]
+--- get or set the description for a single branch id.
+--- The default branch is [$at].
+M.main.desc = function(args)
+  local P = popdir(args)
+  local br, id, bdir = M.resolve(P,
+    args[1] == '--' and 'at' or args[1] or 'at')
+  local desc = shim.popRaw(args) or lines.load(args[2])
+  local oldp = M.patchPath(bdir, id, '.p')
+  if not desc then
+    return print(concat(M.desc(oldp), '\n'))
+  end
+  local newp = sconcat('', bdir, tostring(id), '.p')
+  local n = io.open(newp, 'w')
+  for _, line in ipairs(desc) do n:write(line, '\n') end
+  local o = io.open(oldp, 'r')
+  for line in o:lines() do
+    if isPatchLike(line) then n:write(line, '\n'); break end
+  end
+  for line in o:lines() do n:write(line, '\n') end
+  local back = M.backupDir(P, sfmt('%s#%s', br, id)); ix.mkDir(back)
+  back = back..id..'.p'
+  ix.mv(oldp, back)
+  io.fmt:styled('notify', sfmt('moved %s -> %s', oldp, back), '\n')
+  ix.mv(newp, oldp)
+  io.fmt:styled('notify', 'updated desc of '..oldp, '\n')
+end
+
+--- [$pvc squash [branch#id --num=2]]
+--- sqash branch#id into the [$num] commits before it.
+--- Default (num=2) squashes it into the previous commit.
+---
+--- You can then edit the description by using [$pvc desc].
+M.main.squash = function(args)
+  local P = popdir(args)
+  local br,id = M.resolve(args[1] or 'at')
+  local num = toint(args.num or 2)
+  M.squash(P, br,id, num)

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -96 +96,5 @@
-  T.path(pvc.patchPath(Bm, id, '.p'), DIFF1)
+  local p1 = pvc.patchPath(Bm, id, '.p')
+  T.path(p1, DIFF1)
+  T.eq({'desc1'}, pvc.desc(p1))
+  pvc.main.desc{'--', 'desc1 - edited', dir=D}
+  T.eq({'desc1 - edited'}, pvc.desc(p1))
@@ -202,0 +207 @@
+
@@ -204 +209,4 @@
-  T.path(D..'story.txt', STORY3d:gsub('unhappy', 'happy'))
+  local EXPECT4 = ds.copy(EXPECT3d, {
+    ['story.txt'] = STORY3d:gsub('unhappy', 'happy'),
+  })
+  T.path(D, EXPECT4)
@@ -208 +216 @@
-  T.path(pvc.snapshot(D, 'main', 5), EXPECT5)
+  T.eq({'main', 5}, {pvc.at(D)})
@@ -209,0 +218,10 @@
+  T.path(pvc.snapshot(D, 'main', 5), EXPECT5)
+  T.path(pvc.snapshot(D, 'main', 4), EXPECT4)
+
+  -- Squash main commit and first dev commit
+  pvc.squash(D, 'main', 4, 2)
+  T.path(pvc.snapshot(D, 'main', 2), EXPECT2)
+  T.path(pvc.snapshot(D, 'main', 3), EXPECT4)
+  pvc.at(D, 'main',2); T.path(D, EXPECT2)
+  pvc.at(D, 'main',3); T.path(D, EXPECT4)
+  pvc.at(D, 'main',4); T.path(D, EXPECT5)

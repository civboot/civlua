implement show
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -513 +513,18 @@
-M.checkBranch = function(pdir, dir, checks)
+local NOT_BRANCH = { backup = 1, at = 1}
+local branchesRm = function(a, b) return NOT_BRANCH[a] end
+
+--- get all branches
+M.branches = function(pdir) --> list
+  local entries = {}
+  local d = pdir..'.pvc/'
+  for e in ix.dir(d) do
+    if not NOT_BRANCH[e] and ix.pathtype(d..e) == 'dir' then
+      push(entries, pth.toNonDir(e))
+    end
+  end
+  sort(entries)
+  return entries
+end
+
+M.checkBranch = function(pdir, name, checks, dir)
+  dir = dir or pdir..name
@@ -526,0 +544,3 @@
+  if checks.children then -- check that it has no children
+
+  end
@@ -532 +552 @@
-  M.checkBranch(pdir, from, {base=1})
+  M.checkBranch(pdir, name, {base=1}, from)
@@ -854,0 +875,41 @@
+  end
+end
+
+M.main.show = function(args)
+  local D = popdir(args)
+  local full = args.full
+  if not args[1] then -- just show all branches
+    for _, br in ipairs(M.branches(D)) do
+      if full then
+        local bdir = M.branchPath(D, br)
+        local tip, base,bid = M.rawtip(bdir), M.getbase(bdir, nil)
+        io.user:styled('notify', sfmt('%s\ttip=%s%s',
+          br, tip, base and sfmt('\tbase=%s#%s', base,bid) or ''), '\n')
+      else io.user:styled('notify', br, '\n') end
+    end
+    return
+  end
+  local br, id = M.parseBranch(args[1])
+  if not br or br == 'at' then br, id = M.rawat(D) end
+
+  local num, dir = toint(args.num or 10), M.branchPath(D, br)
+  if not id then id = M.rawtip(dir) end
+  local bbr, bid = M.getbase(dir)
+  for i=id,id-num+1,-1 do
+    if i <= 0 then break end
+    if i == bid then
+      br, dir = bbr, M.branchPath(D, bbr)
+      bbr, bid = M.getbase(dir)
+    end
+    local ppath = M.patchPath(dir, i, '.p')
+    local desc = {}
+    for line in io.lines(ppath) do
+      if line:sub(1,2) == '!!' or line:sub(1,3) == '---'
+        then break end
+      push(desc, line); if not full then break end
+    end
+    io.user:styled('notify', sfmt('%s#%s:', br,i), '')
+    io.user:level(1)
+    io.user:write(full and '\n' or ' ', concat(desc, '\n'))
+    io.user:level(-1)
+    io.user:write'\n'

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -49,0 +50 @@
+  T.eq({'main'}, pvc.branches(D))
@@ -156,0 +158 @@
+  T.eq({'dev', 'main'}, pvc.branches(D))

--- lib/civix/civix.lua
+++ lib/civix/civix.lua
@@ -304,12 +303,0 @@
---- A very simple ls (list paths) implementation
---- Returns (files, dirs) tables. Anything that is not a directory
---- is treated as a file.
-M.ls = function(paths, maxDepth)
-  local files, dirs = {}, {}
-  M.walk(paths, {
-    dir     = function(p) push(dirs,  pc{p, '/'}) end,
-    default = function(p) push(files, p)          end,
-  }, maxDepth or 1)
-  return files, dirs
-end
-

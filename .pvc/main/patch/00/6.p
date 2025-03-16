--- cmd/pvc/README.cxt
+++ cmd/pvc/README.cxt
@@ -14,3 +13,0 @@
-* [$rebase [branch [id]]]: change the base of branch to id.
-  (default branch=current, id=branch base's tip)
-
@@ -39,0 +37,8 @@
+* [$rebase [branch [id]]]: change the base of branch to id.
+  (default branch=current, id=branch base's tip)
+
+* [$grow from]: copy the commits at [$from] onto current branch.
+  The base of [$from] must be the current branch's tip.
+  Then move the branch to backup.
+  ["in git this is a "fast forward" merge]
+
@@ -51,0 +57,35 @@
+
+[{h2}Usage]
+First install [@Package_civ], then run pvc in bash with [$civ.lua pvc <cmd>].
+
+To track an existing directory:[+
+* [$cd path/to/dir] to navigate to the directory
+* [$pvc init] to initialize pvc
+* [$pvc diff] prints the diff of local changes to stderr and untracked files
+  (that are not matched in [$.pvcignore] to stdout. Edit [$.pvcignore]
+  with appropriate entries (see [@pvcignore]) to ignore paths you don't
+  want tracked until [$pvc diff] shows only files you want tracked.
+
+  When ready, running [$pvc diff >> .pvcpaths] in bash will track all untracked
+  files.
+  ["Alternatively, manually add files to [$.pvcpaths]]
+* [$pvc commit -- initial pvc commit] will commit your changes to
+  [$.pvc/main/patch/.../1.p].
+]
+
+[{:h3}pvcignore]
+The [$.pvcignore] file should contain a line-separated list of lua patterns
+([@lua.find]) that should be ignored. Items ending in [$/] will apply to
+whole directories. A common pvc ignore file might look like:
+
+[##
+# directories
+%.git/
+%.out/
+
+# extensions
+%.so$
+
+# specific files
+%./path/to/some_file
+]##

--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -155,0 +156 @@
+
@@ -174,0 +176,4 @@
+M.Diff.hasDiff = function(d)
+  return (#d.changed > 0) or (#d.deleted > 0) or (#d.created > 0)
+end
+
@@ -186,3 +191 @@
-    if (#d.changed == 0) and (#d.deleted == 0) and (#d.created == 0) then
-      return s('bold', 'No Difference')
-    end
+    if not d:hasDiff() then return s('bold', 'No Difference') end
@@ -361 +364 @@
-      io.user:styled('meta',  sfmt('keeping changed %s', path), '\n')
+      io.fmt:styled('meta',  sfmt('keeping changed %s', path), '\n')
@@ -363 +366 @@
-      io.user:styled('error', sfmt('path %s changed',    path), '\n')
+      io.fmt:styled('error', sfmt('path %s changed',    path), '\n')
@@ -396 +399 @@
-  io.user:styled('notify', sfmt('pvc: at %s#%s', nbr,nid), '\n')
+  io.fmt:styled('notify', sfmt('pvc: at %s#%s', nbr,nid), '\n')
@@ -449 +452 @@
-  io.user:styled('notice', 'initialized pvc repo '..dot, '\n')
+  io.fmt:styled('notice', 'initialized pvc repo '..dot, '\n')
@@ -539 +542 @@
-      io.user:styled('error', sfmt(
+      io.fmt:styled('error', sfmt(
@@ -547,4 +550,3 @@
---- create a backup directory and return it
-M.createBackup = function(P, name) --> string
-  local b = sfmt('%s.pvc/backup/%s-%s/', P, name, M.backupId())
-  ix.mkDir(b); return b
+--- return a backup directory (uses the timestamp)
+M.backupDir = function(P, name) --> string
+  return sfmt('%s.pvc/backup/%s-%s/', P, name, M.backupId())
@@ -605 +607 @@
-  local backup = M.createBackup(pdir, cbr)
+  local backup = M.backupDir(pdir, cbr); ix.mkDir(backup)
@@ -607 +609 @@
-  io.user:styled('notify',
+  io.fmt:styled('notify',
@@ -615,0 +618,26 @@
+--- Grow [$to] by copying patches [$from]
+M.grow = function(P, from, to) --!!>
+  local fdir = M.branchPath(P, from)
+  local bbr, bid = M.getbase(fdir)
+  local tbr = tbr or M.at()
+  if bbr ~= tbr then error(sfmt(
+    'the base of %s is %s, not %s', from, bbr, tbr
+  ))end
+  local tdir = M.branchPath(P, tbr)
+  local ttip = M.rawtip(tdir)
+  if bid ~= ttip then error(sfmt(
+    'rebase required (%s tip=%s, %s base id=%s)', tbr, ttip, bbr, bid
+  ))end
+  -- TODO(sig): check signature
+  for id=bid+1, M.rawtip(fdir) do
+    local tpath = M.patchPath(tdir, id, '.p')
+    assert(not ix.exists(tpath))
+    local fpath = M.patchPath(fdir, id, '.p')
+    info('copying: %s -> %s', fpath, tpath)
+    ix.forceCp(fpath, tpath)
+  end
+  ix.mv(fdir, M.backupDir(fbr))
+  io.fmt:styled('notify', sfmt('grew %s to %s', tbr, ftip), '\n')
+  if not to then ix.at(to, ftip) end
+end
+
@@ -644,0 +673,4 @@
+M.main.grow = function(args)
+  local P = popdir(args)
+end
+
@@ -761 +793 @@
-  io.user:styled('notify', sfmt('exported %s to %s', bdir, to))
+  io.fmt:styled('notify', sfmt('exported %s to %s', bdir, to))
@@ -784 +816 @@
-    io.user:styled('notify', sfmt('pruned [%s -> %s]. Undo with %s',
+    io.fmt:styled('notify', sfmt('pruned [%s -> %s]. Undo with %s',
@@ -788 +820 @@
-    io.user:styled('notify', sfmt('moved %s -> %s', bdir, back))
+    io.fmt:styled('notify', sfmt('moved %s -> %s', bdir, back))
@@ -796 +828 @@
-    io.user:styled('error', cmd..' is not recognized', '\n')
+    io.fmt:styled('error', cmd..' is not recognized', '\n')

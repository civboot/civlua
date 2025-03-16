--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -43 +43 @@
-M.backupId = function() return toint(ix.epoch().s) end
+M.backupId = function() return tostring(ix.epoch():asSeconds()) end
@@ -552 +552,6 @@
-  return sfmt('%s.pvc/backup/%s-%s/', P, name, M.backupId())
+  for _=1,10 do
+    local b = sfmt('%s.pvc/backup/%s-%s/', P, name, M.backupId())
+    print('!! backupDir', b)
+    if ix.exists(b) then ix.sleep(0.01) else return b end
+  end
+  error('could not find empty backup')
@@ -619,2 +624,3 @@
-M.grow = function(P, from, to) --!!>
-  local fdir = M.branchPath(P, from)
+M.grow = function(P, to, from) --!!>
+  local fbr, fdir = assert(from, 'must set from'), M.branchPath(P, from)
+  local ftip = M.rawtip(fdir)
@@ -622 +628 @@
-  local tbr = tbr or M.at()
+  local tbr = to or M.rawat(P)
@@ -630,0 +637,3 @@
+  if ftip == bid then error(sfmt(
+    "rebase not required: %s base is equal to it's tip (%s)", fbr, bid
+  ))end
@@ -639,2 +648,7 @@
-  ix.mv(fdir, M.backupDir(fbr))
-  io.fmt:styled('notify', sfmt('grew %s to %s', tbr, ftip), '\n')
+  M.rawtip(tdir, ftip)
+  local back = M.backupDir(P, fbr)
+  assert(not ix.exists(back), 'WHAT: '..back)
+  io.fmt:styled('notify',
+    sfmt('deleting %s (mv %s -> %s)', fbr, fdir, back), '\n')
+  ix.mv(fdir, back)
+  io.fmt:styled('notify', sfmt('grew %s tip to %s', tbr, ftip), '\n')
@@ -672,0 +687 @@
+--- [$grow from --to=at]: grow [$to] (default=[$at]) using branch from.
@@ -674,0 +690 @@
+  return M.grow(P, args.to, args[1])
@@ -768 +784,2 @@
-  return M.branch(D, name, fbr,fid)
+  local bpath, id = M.branch(D, name, fbr,fid)
+  M.at(D, name)

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -201,0 +202,5 @@
+
+  pvc.grow(D, 'main', 'dev')
+  T.eq(5, pvc.rawtip(Bm))
+  T.path(pvc.snapshot(D, 'main', 5), EXPECT5)
+  assert(not ix.exists(Bd))

--- lib/civtest/civtest.lua
+++ lib/civtest/civtest.lua
@@ -61,2 +61,4 @@
-  io.fmt:styled('error', sfmt('!! Path %s != %s', a, b), '\n')
-  showDiff(at, bt); fail'Test.pathEq'
+  showDiff(at, bt);
+  io.fmt:styled('error', sfmt('Path expected: %s\n       result: %s',
+    a, b), '\n')
+  fail'Test.pathEq'

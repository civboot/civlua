first commit with a commit message
hopefully it works
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -460 +460,10 @@
-M.commit = function(pdir) --> snap/, id
+M.commit = function(pdir, desc) --> snap/, id
+  assert(desc, 'commit must provide description')
+  if   desc:sub(1,3) == '---' or desc:find('\n---', 1, true)
+    or desc:sub(1,3) == '+++' or desc:find('\n+++', 1, true)
+    or desc:sub(1,2) == '!!'  or desc:find('\n!!',  1, true)
+    then error(
+      "commit message cannot have any of the following"
+    .." at the start of a line: +++, ---, !!"
+  )end
+
@@ -476 +485 @@
-                M.Diff:of(bsnap, pdir):patch())
+    sconcat('\n', desc, M.Diff:of(bsnap, pdir):patch()))
@@ -765,2 +774,9 @@
---- specified after the [$--] argument.
-M.main.commit = function(args) M.commit(popdir(args)) end
+--- specified after the [$--] argument, where multiple arguments are newline
+--- separated.
+M.main.commit = function(args)
+  local P = popdir(args)
+  local desc = shim.popRaw(args)
+  if desc then desc = concat(desc, '\n')
+  else         desc = pth.read(P..'COMMIT') end
+  M.commit(P, desc)
+end

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -79,0 +80 @@
+  desc1
@@ -93 +94 @@
-  local br, id = pvc.commit(D)
+  local br, id = pvc.commit(D, 'desc1')
@@ -126 +127 @@
-    pvc.commit(D)
+    pvc.commit(D, 'desc error')
@@ -146 +147 @@
-  pvc.commit(D)
+  pvc.commit(D, 'desc2')
@@ -160 +161 @@
-  pvc.commit(D)
+  pvc.commit(D, 'desc3d')
@@ -169 +170 @@
-  pvc.commit(D)
+  pvc.commit(D, 'desc4d')
@@ -180 +181 @@
-  pvc.commit(D)
+  pvc.commit(D, 'desc3')

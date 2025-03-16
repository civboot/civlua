better commit print
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -484 +484,2 @@
-  ix.forceWrite(M.patchPath(bp, cid, '.p'),
+  local patchf = M.patchPath(bp, cid, '.p')
+  ix.forceWrite(patchf,
@@ -491 +492 @@
-  info('commited %s#%s', br, cid)
+  io.fmt:styled(sfmt('commited %s#%s to %s', br, cid, patchf), '\n')

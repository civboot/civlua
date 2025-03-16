there we go
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -492 +492 @@
-  io.fmt:styled(sfmt('commited %s#%s to %s', br, cid, patchf), '\n')
+  io.fmt:styled('notify', sfmt('commited %s#%s to %s', br, cid, patchf), '\n')

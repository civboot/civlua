--- .pvcignore
+++ .pvcignore
@@ -0,0 +1 @@
+# directories
@@ -4,0 +6,2 @@
+
+# extensions
@@ -10,0 +14,2 @@
+
+# binaries

--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -63,2 +63,6 @@
-  local ignore = lines.load(P..'.pvcignore')
-  push(ignore, '%.pvc/')
+  local ignore = {'%./%.pvc/'}
+  for line in io.lines(P..'.pvcignore') do
+    if line == '' or line:sub(1,1) == '#' then --ignore
+    else push(ignore, line)
+    end
+  end
@@ -175 +179,3 @@
-      if     line:sub(1,1) == '-' then s('base',   line, '\n')
+      local l2 = line:sub(1,2)
+      if l2 == '--' or l2 == '++' or l2 == '@@' then s('notify', line, '\n')
+      elseif line:sub(1,1) == '-' then s('base',   line, '\n')
@@ -695,0 +702 @@
+  trace('diff%q', args)
@@ -786 +793 @@
-  args = shim.parse(args)
+  trace('pvc%q', args)

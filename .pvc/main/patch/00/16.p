add checks for binary and empty files
--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -1033 +1033 @@
-  local br,bot = M.resolve(P, args[1] or 'at')
+  local br,bot = M.resolve(P, assert(args[1], 'must set branch#id (aka "at")'))

--- cmd/pvc/pvc/unix.lua
+++ cmd/pvc/pvc/unix.lua
@@ -11,0 +12 @@
+local sfmt = string.format
@@ -18 +19,2 @@
-@@ -0,0 +0,0 @@
+@@ -0,0 +0,1 @@
++
@@ -20,0 +23,8 @@
+local diffCheckPath = function(p, pl) --> p, pl
+  if not p then return NULL, NULL end
+  if ix.stat(p):size() == 0 then error(
+    p..' has a size of 0, which patch cannot handle'
+  )end
+  return p, pl
+end
+
@@ -26,2 +36,2 @@
-  if not a then a, al = NULL, NULL end
-  if not b then b, bl = NULL, NULL end
+  a, al = diffCheckPath(a, al)
+  b, bl = diffCheckPath(b, bl)
@@ -33 +43,6 @@
-  if sh:rc() == 1 then
+  if o then
+    if sh:rc() ~= 1 then error('unknown return code: '..sh:rc()) end
+    if o:sub(1,3) ~= '---' then
+      error(sfmt('non-diff output from diff %q %q:\n%s\n%s',
+                                            al,bl,  o,  e))
+    end
@@ -36 +51 @@
-  return EMPTY_DIFF:format(al, bl)
+  error((a or b)..' is empty (https://stackoverflow.com/questions/44427545)')
@@ -40 +55 @@
-  return {'patch', '-p0', '-fu', input=pth.abs(path), CWD=cwd}
+  return {'patch', '-p0', '--binary', '-fu', input=pth.abs(path), CWD=cwd}

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -23,0 +24,27 @@
+local initPvc = function(d)
+  d = d or D
+  ix.rmRecursive(d);
+  pvc.init(d)
+  return d
+end
+
+--- test empty files
+T.empty = function()
+  local d = initPvc()
+  pth.write(d..'empty.txt', '')
+  pth.append(d..'.pvcpaths', 'empty.txt')
+  T.throws('has a size of 0', function()
+    pvc.commit(d, 'commit empty.txt')
+  end)
+end
+
+T.binary = function()
+  local P = initPvc()
+  local bpath, BIN = P..'bin', '\x00\xFF'
+  pth.write(bpath, BIN)
+  pth.append(P..'.pvcpaths', 'bin')
+  T.throws('Binary files /dev/null and bin differ', function()
+    pvc.commit(P, 'commit binary file')
+  end)
+end
+
@@ -228,0 +256 @@
+

--- lib/civix/civix/lib.c
+++ lib/civix/civix/lib.c
@@ -181,0 +182,7 @@
+// stat -> (size)
+static int l_stat_size(LS *L) {
+  STAT* st = *tolstat(L);
+  printf("!! stat_size %i\n", st->st_size);
+  lua_pushinteger(L, st->st_size); return 1;
+}
+
@@ -332,0 +340 @@
+      L_setmethod(L, "size",     l_stat_size);

--- lib/civix/test.lua
+++ lib/civix/test.lua
@@ -172,0 +173,6 @@
+
+T.stat = function()
+  local path = O..'stat.txt'
+  pth.write(path, 'hello\n')
+  T.eq(6, M.stat(path):size())
+end

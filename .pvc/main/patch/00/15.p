squash should work, but is rather hard to test

--- cmd/pvc/pvc.lua
+++ cmd/pvc/pvc.lua
@@ -711,5 +711,8 @@
-M.squash = function(P, br,id, num)
-  trace('squash %s %s %s', br, id, num)
-  assert(br and id and num, 'must set all args')
-  assert(id > 0)
-  assert(num > 1, 'num must be >= 2')
+M.squash = function(P, br, bot,top)
+  trace('squash %s [%s %s]', br, bot,top)
+  assert(br and bot and top, 'must set all args')
+  assert(top > 0)
+  if top - bot <= 0 then
+    io.fmt:notify('error', 'squashing ids [%s - %s] is a noop', bot, top)
+    return
+  end
@@ -718,4 +721,3 @@
-  local bot = id - num + 1
-  if bot <= bid then error(sfmt('bottom %i <= base id %s', id, bid)) end
-  if id  >  tip then error(sfmt('id %i > tip %i', id, tip)) end
-  M.at(P, br,id)
+  if bot <= bid  then error(sfmt('bottom %i <= base id %s', top, bid)) end
+  if top  >  tip then error(sfmt('top %i > tip %i', top, tip)) end
+  M.at(P, br,top)
@@ -727 +729 @@
-  local patch = M.Diff:of(M.snapshot(P, br,bot-1), M.snapshot(P, br,id))
+  local patch = M.Diff:of(M.snapshot(P, br,bot-1), M.snapshot(P, br,top))
@@ -729 +731 @@
-  for i=bot,id do
+  for i=bot,top do
@@ -737 +739 @@
-  local f = io.open(M.patchPath(bdir, id, '.p'), 'w')
+  local f = io.open(M.patchPath(bdir, top, '.p'), 'w')
@@ -743 +745 @@
-  for i=id+1, tip do
+  for i=top+1, tip do
@@ -755 +757 @@
-    sfmt('squashed [%s - %s] into %s', bot, id, ppath), '\n')
+    sfmt('squashed [%s - %s] into %s', bot, top, ppath), '\n')
@@ -947,0 +950,8 @@
+--- [$pvc show [branch#id] --num=10 --full]
+---
+--- If no branch is specified: show branches. [$full] also displays
+--- the base and tip.
+---
+--- Else show branch#id and the previous [$num] commit messages.
+--- With [$full] show the full commit message, else show only
+--- the first line.
@@ -987,0 +998,3 @@
+---
+--- The new description can be passed via [$path/to/new] or
+--- after [$--] (like commit).
@@ -1013,3 +1026,2 @@
---- [$pvc squash [branch#id --num=2]]
---- sqash branch#id into the [$num] commits before it.
---- Default (num=2) squashes it into the previous commit.
+--- [$pvc squash [branch#id endId]]
+--- squash branch id -> endId (inclusive) into a single patch at [$id].
@@ -1017 +1029 @@
---- You can then edit the description by using [$pvc desc].
+--- You can then edit the description by using [$pvc desc branch#id].
@@ -1018,0 +1031 @@
+  trace('squash%q', args)
@@ -1020,3 +1033,3 @@
-  local br,id = M.resolve(args[1] or 'at')
-  local num = toint(args.num or 2)
-  M.squash(P, br,id, num)
+  local br,bot = M.resolve(P, args[1] or 'at')
+  local top = toint(assert(args[2], 'must set endId'))
+  M.squash(P, br, bot,top)

--- cmd/pvc/test.lua
+++ cmd/pvc/test.lua
@@ -222 +222 @@
-  pvc.squash(D, 'main', 4, 2)
+  pvc.squash(D, 'main', 3,4)

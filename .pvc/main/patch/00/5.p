--- lib/pkg/README.cxt
+++ lib/pkg/README.cxt
@@ -24,2 +24 @@
-In your [$~/.bashrc] or equiavalent add:
-```
+In your [$~/.bashrc] or equiavalent add: [{## lang=sh}
@@ -28 +27 @@
-```
+]##
@@ -31 +30 @@
-[$lua -e \"require'pkglib'.install()\"; G.MAIN = {}" -i]
+[$lua -e \"require'pkglib'()\"; G.MAIN = {}" -i]

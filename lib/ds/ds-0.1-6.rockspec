build = {
  modules={
    ds="ds.lua",
    ["ds.diff"]="ds/diff.lua",
    ["ds.file"]="ds/file.lua",
    ["ds.heap"]="ds/heap.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "metaty ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/ds/README.md",
  license="UNLICENSE",
  summary="Tiny data structures and algorithms"
}
package = "ds"
rockspec_format = "3.0"
source = {
  dir="lib/ds",
  tag="ds-0.1-6",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-6"

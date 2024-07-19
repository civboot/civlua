build = {
  modules={
    ds="ds.lua",
    ["ds.Grid"]="ds/Grid.lua",
    ["ds.file"]="ds/file.lua",
    ["ds.heap"]="ds/heap.lua",
    ["ds.log"]="ds/log.lua",
    ["ds.utf8"]="ds/utf8.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
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
  dir="civlua/lib/ds",
  tag="ds-0.1-12",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-12"
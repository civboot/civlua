build = {
  modules={
    ds="ds.lua",
    ["ds.Grid"]="ds/Grid.lua",
    ["ds.Iter"]="ds/Iter.lua",
    ["ds.LL"]="ds/LL.lua",
    ["ds.heap"]="ds/heap.lua",
    ["ds.log"]="ds/log.lua",
    ["ds.path"]="ds/path.lua",
    ["ds.utf8"]="ds/utf8.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1"
}
description = {
  homepage="https://lua.civboot.org#Package_ds",
  license="UNLICENSE",
  summary="Tiny data structures and algorithms"
}
package = "ds"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/ds",
  tag="ds-0.1-13",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-13"

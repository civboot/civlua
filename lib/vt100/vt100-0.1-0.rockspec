build = {
  modules={
    vt100="vt100.lua",
    ["vt100.testing"]="vt100/testing.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/vt100/README.md",
  license="UNLICENSE",
  summary="Civboot VT100 Terminal Library"
}
package = "vt100"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/vt100",
  tag="vt100-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"

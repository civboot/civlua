build = {
  modules={
    cxt="cxt.lua",
    ["cxt.html"]="cxt/html.lua"
  },
  type="builtin"
}
dependencies = {
  "lua     ~> 5.3",
  "pkg     ~> 0.1",
  "civtest ~> 0.1",
  "ds      ~> 0.1",
  "pegl    ~> 0.1",
  "metaty  ~> 0.1",
  "shim    ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/cmd/cxt/README.md",
  license="UNLICENSE",
  summary="text markup for civilization"
}
package = "cxt"
rockspec_format = "3.0"
source = {
  dir="cmd/cxt",
  tag="cxt-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"

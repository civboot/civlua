build = {
  modules={shim="shim.lua"},
  type="builtin"
}
dependencies = {"lua ~> 5.3"}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/shim/README.md",
  license="UNLICENSE",
  summary="write scripts for Lua, execute from shell"
}
package = "shim"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/shim",
  tag="shim-0.1-5",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-5"

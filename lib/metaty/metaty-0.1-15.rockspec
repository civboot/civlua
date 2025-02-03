build = {
  modules={
    metaty="metaty.lua",
    ["metaty.native"]="metaty.c"
  },
  type="builtin"
}
dependencies = {"lua ~> 5.3"}
description = {
  homepage="https://lua.civboot.org#Package_metaty",
  license="UNLICENSE",
  summary="Simple but effective Lua type system using metatables"
}
package = "metaty"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/metaty",
  tag="metaty-0.1-15",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-15"

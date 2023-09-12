package = "metaty"
version = "0.1-1"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git"
  dir = "metaty/"
}
description = {
  summary = " simple but effective Lua type system using metatables",
  homepage = "https://github.com/civboot/civlua/metaty/README.md",
  license = "UNLICENSE"
}
dependencies = {
  "lua ~> 5.3",
}
build = {
  type = "builtin",
  modules = {
    metaty = "metaty.lua",
  },
  copy_directories = {
    "tests"
  }
}

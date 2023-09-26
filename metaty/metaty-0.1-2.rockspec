package = "metaty"
version = "0.1-2"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "metaty/",
  tag = 'metaty-'..version,
}
description = {
  summary = "Simple but effective Lua type system using metatables",
  homepage = "https://github.com/civboot/civlua/blob/main/metaty/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
}
build = {
  type = "builtin",
  modules = {
    metaty = "metaty.lua",
  },
}

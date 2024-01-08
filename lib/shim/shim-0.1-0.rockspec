package = "shim"
version = "0.1-0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "shim/",
  tag = 'shim-'..version,
}
description = {
  summary = "shim: write scripts for Lua, execute from shell",
  homepage = "https://github.com/civboot/civlua/blob/main/shim/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
}
build = {
  type = "builtin",
  modules = {
    shim = "shim.lua",
  },
}

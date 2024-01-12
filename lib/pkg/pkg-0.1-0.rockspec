package = "pkg"
version = "0.1-0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "lib/pkg/",
  tag = 'pkg-'..version,
}
description = {
  summary = "Lua package definition and loading",
  homepage = "https://github.com/civboot/civlua/blob/main/lib/pkg/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
}
build = {
  type = "builtin",
  modules = {
    metaty = "pkg.lua",
  },
}

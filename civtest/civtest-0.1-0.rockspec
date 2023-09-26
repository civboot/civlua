package = "civtest"
version = "0.1-0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "civtest/",
  tag = 'civtest-'..version,
}
description = {
  summary = "Simple but effective Lua type system using metatables",
  homepage = "https://github.com/civboot/civlua/blob/main/civtest/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
  "metaty ~> 0.1",
  "ds ~> 0.1",
}
build = {
  type = "builtin",
  modules = {
    civtest = "civtest.lua",
  },
}

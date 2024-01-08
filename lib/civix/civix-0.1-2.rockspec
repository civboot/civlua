package = "civix"
version = "0.1-2"
rockspec_format = "3.0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "civix/",
  tag = 'civix-'..version,
}
description = {
  summary = "Simple but effective Lua type system using metatables",
  homepage = "https://github.com/civboot/civlua/blob/main/civix/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
  "metaty ~> 0.1",
  "ds ~> 0.1",
  "luaposix ~> 36.2", -- TODO: would be good to find the minimum version
}
test_dependencies = {
  "civtest ~> 0.1",
}
build = {
  type = "builtin",
  modules = {
    civix = "civix.lua",
  },
}

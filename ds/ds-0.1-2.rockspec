package = "ds"
version = "0.1-2"
rockspec_format = "3.0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "ds/",
  tag = 'ds-'..version,
}
description = {
  summary = "Simple but effective Lua type system using metatables",
  homepage = "https://github.com/civboot/civlua/blob/main/ds/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
  "metaty ~> 0.1",
}
test_dependencies = {
  "civtest ~> 0.1",
}
build = {
  type = "builtin",
  modules = {
    ds = "ds.lua",
  },
}

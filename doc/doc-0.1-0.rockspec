package = "doc"
version = "0.1-0"
source = {
  url = "git+ssh://git@github.com/civboot/civlua.git",
  dir = "doc/",
  tag = 'doc-'..version,
}
description = {
  summary = "Documentation and help for Lua types (including core)",
  homepage = "https://github.com/civboot/civlua/blob/main/doc/README.md",
  license = "UNLICENSE",
}
dependencies = {
  "lua ~> 5.3",
  "metaty ~> 0.1-5",
}
build = {
  type = "builtin",
  modules = {
    doc = "doc.lua",
  },
}

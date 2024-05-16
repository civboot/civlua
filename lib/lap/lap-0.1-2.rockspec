build = {
  modules={lap="lap.lua"},
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/lap/README.md",
  license="UNLICENSE",
  summary="Lua Asynchronous Protocol and helper library"
}
package = "lap"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/lap",
  tag="lap-0.1-2",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-2"

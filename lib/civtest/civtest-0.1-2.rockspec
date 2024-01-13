build = {
  modules={
    civtest="civtest.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/civtest/README.md",
  license="UNLICENSE",
  summary="Ultra simple testing library"
}
package = "civtest"
rockspec_format = "3.0"
source = {
  dir="lib/civtest",
  tag="civtest-0.1-2",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-2"

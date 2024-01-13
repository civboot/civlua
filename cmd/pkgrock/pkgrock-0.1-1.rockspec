build = {
  modules={
    pkgrock="pkgrock.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "shim   ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/cmd/pkgrock/README.md",
  license="UNLICENSE",
  summary="pkg utilities to work with rockspecs"
}
package = "pkgrock"
rockspec_format = "3.0"
source = {
  dir="cmd/pkgrock",
  tag="pkgrock-0.1-1",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-1"

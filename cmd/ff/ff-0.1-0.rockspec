build = {
  modules={
    ff="ff.lua"
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
  homepage="https://github.com/civboot/civlua/blob/main/cmd/ff/README.md",
  license="UNLICENSE",
  summary="find+fix files"
}
package = "ff"
rockspec_format = "3.0"
source = {
  dir="cmd/ff",
  tag="ff-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"

build = {
  modules={
    fd="fd.lua",
    ["fd.sys"]="fd.c"
  },
  type="builtin"
}
dependencies = {
  "lua ~> 5.3",
  "pkg ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/fd/README.md",
  license="UNLICENSE",
  summary="filedescriptor interfaces"
}
package = "fd"
rockspec_format = "3.0"
source = {
  dir="lib/fd",
  tag="fd-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"
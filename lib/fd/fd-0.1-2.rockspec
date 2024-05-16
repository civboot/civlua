build = {
  modules={
    fd="fd.lua",
    ["fd.sys"]="fd.c"
  },
  type="builtin"
}
dependencies = {"lua ~> 5.3"}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/fd/README.md",
  license="UNLICENSE",
  summary="filedescriptor interfaces"
}
package = "fd"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/fd",
  tag="fd-0.1-2",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-2"

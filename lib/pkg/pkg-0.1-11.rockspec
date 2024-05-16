build = {
  modules={pkg="pkglib.lua"},
  type="builtin"
}
dependencies = {"lua ~> 5.3"}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/pkg/README.md",
  license="UNLICENSE",
  summary="better lua package creation and importing"
}
package = "pkg"
rockspec_format = "3.0"
source = {
  dir='civlua/lib/pkg',
  tag="pkg-0.1-11",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-11"
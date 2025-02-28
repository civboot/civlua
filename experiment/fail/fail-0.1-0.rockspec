build = {
  modules={fail="fail.lua"},
  type="builtin"
}
dependencies = {"lua ~> 5.3"}
description = {
  homepage="https://lua.civboot.org#Package_fail",
  license="UNLICENSE",
  summary="an ergonomic mechanism to return failure"
}
package = "fail"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/fail",
  tag="fail-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"

build = {
  modules={lson="lson.lua"},
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/lson/README.md",
  license="UNLICENSE",
  summary="JSON+ de/serializer in pure lua"
}
package = "lson"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/lson",
  tag="lson-0.1-0",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-0"

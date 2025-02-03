build = {
  modules={
    pod="pod.lua",
    ["pod.native"]="pod.c",
    ["pod.testing"]="pod/testing.lua"
  },
  type="builtin"
}
dependencies = {
  "lua    ~> 5.3",
  "metaty ~> 0.1"
}
description = {
  homepage="https://lua.civboot.org#Package_ds",
  license="UNLICENSE",
  summary="Plain old data (POD) de/serialization"
}
package = "pod"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/pod",
  tag="pod-0.1-1",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-1"

build = {
  modules={
    civix="civix.lua",
    ["civix.lib"]="civix/lib.c",
    ["civix.term"]="civix/term.lua"
  },
  type="builtin"
}
dependencies = {
  "lua ~> 5.3",
  "shim   ~> 0.1",
  "fd     ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
  "lap    ~> 0.1"
}
description = {
  homepage="https://github.com/civboot/civlua/blob/main/lib/civix/README.md",
  license="UNLICENSE",
  summary="Unix sys library"
}
package = "civix"
rockspec_format = "3.0"
source = {
  dir="civlua/lib/civix",
  tag="civix-0.1-8",
  url="git+http://github.com/civboot/civlua"
}
version = "0.1-8"

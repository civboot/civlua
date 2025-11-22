summary"version control data structures and algorithms"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}

pkg {
  name     = 'vcds',
  version  = '0.1-6',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_vcds",
  license  = "UNLICENSE",
}
P.vcds = lua {
  srcs = { 'vcds.lua' },
}

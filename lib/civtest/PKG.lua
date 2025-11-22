summary"Ultra simple testing library"
import {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}

local P = pkg {
  name     = 'civtest',
  version  = '0.1-2',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_civtest",
  license  = "UNLICENSE",
  doc = 'README.cxt',
}

P.lua = lua {
  src = { 'civtest.lua' },
}

return P

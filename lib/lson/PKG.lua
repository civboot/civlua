summary"JSON+ de/serializer in pure lua"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}

local P = pkg {
  name     = 'lson',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_lson",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.lua = lua {
  src = { 'lson.lua' },
}

return P

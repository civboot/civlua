summary"Lua Asynchronous Protocol and helper library"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1",
  "ds     ~> 0.1",
}
pkg {
  name     = 'lap',
  version  = '0.1-3',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org#Package_lap',
  license  = 'UNLICENSE',
  doc      = 'README.cxt',
}

P.lap = lua {
  src = { 'lap.lua' },
}

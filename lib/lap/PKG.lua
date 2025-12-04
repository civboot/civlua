summary"Lua Asynchronous Protocol and helper library"
import {
  lua    = 'sys:lua',
  metaty = 'civ:lib/metaty',
  fmt    = 'civ:lib/fmt',
  ds     = 'civ:lib/ds',
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
  mod = 'lap',
  src = { 'lap.lua' },
  dep = {
    metaty.metaty,
    fmt.fmt,
    ds.ds,
  }
}

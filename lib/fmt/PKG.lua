summary"format and style anything"
import {
  metaty = "civ:lib/metaty",
}
pkg {
  name     = 'fmt',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org#Package_fmt',
  license  = 'UNLICENSE',
}

P.fmt = lua {
  mod = 'fmt',
  src = {
    'fmt.lua',
    'binary.lua',
  },
  dep = {
    metaty,
  },
}

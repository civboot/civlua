summary"format and style anything"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
}
pkg {
  name     = 'fmt',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org#Package_fmt',
  license  = 'UNLICENSE',
}

P.fmt = lua {
  src = {
    'fmt.lua',
    ['fmt.binary'] = 'binary.lua',
  },
}

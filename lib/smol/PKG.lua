summary"compression algorithms"
import {
  "lua ~> 5.3",
}

pkg {
  name = 'smol',
  homepage = "https://lua.civboot.org#Package_smol",
  license  = "UNLICENSE",
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  doc      = 'README.cxt',
}

P.smol = lua {
  src = {
    'smol.lua',
    ['smol.sys'] = 'smol.c',
  },
  lib = {
    ['smol.sys'] = 'smol.so',
  },
}

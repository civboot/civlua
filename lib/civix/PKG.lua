summary"Unix sys library"
import {
  cc   = 'sys:cc',
  lua  = 'sys:lua',
  ds   = 'civ:lib/ds',
  shim = 'civ:lib/shim',
  fd   = 'civ:lib/fd',
  lap  = 'civ:lib/lap',
}

pkg {
  name     = 'civix',
  homepage = "https://lua.civboot.org#Package_civix",
  license  = "UNLICENSE",
  version  = '0.1-8',
  url      = 'git+http://github.com/civboot/civlua',
  doc      = 'README.cxt',
}

P.civixlib = cc {
  lib = 'civix',
  src = 'civix.c',
}

P.civix = lua {
  mod = 'civix',
  src = {
    'civix.lua',
    'testing.lua',
  },
  lib = P.civixlib,
  dep = {
    ds.ds,
    shim.shim,
    fd.fd,
    lap.lap,
  },
}

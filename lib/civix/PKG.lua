summary"Unix sys library"
import {
  "lua ~> 5.3",
  "shim   ~> 0.1",
  "fd     ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
  "lap    ~> 0.1",
}

pkg {
  name     = 'civix',
  homepage = "https://lua.civboot.org#Package_civix",
  license  = "UNLICENSE",
  version  = '0.1-8',
  url      = 'git+http://github.com/civboot/civlua',
  doc      = 'README.cxt',
}

P.civix = lua {
  src = {
    'civix.lua',
    ['civix.lib'] = 'civix.c',
    'civix/testing.lua',
  },
  lib = {
    ['civix.lib'] = 'civix.so',
  },
}

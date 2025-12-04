summary"Plain old data (POD) de/serialization"
import {
  cc     = 'sys:cc',
  lua    = 'sys:lua',
  metaty = 'civ:lib/metaty',
}

pkg {
  name     = 'pod',
  version  = '0.1-3',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_pod",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.podlib = cc {
  lib = 'pod',
  hdr = 'pod.h',
  src = 'pod.c',
}

P.pod = lua {
  mod = 'pod',
  src = { 'pod.lua' },
  dep = { metaty.metaty },
  lib = P.podlib,
}

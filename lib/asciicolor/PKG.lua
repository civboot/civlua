summary"encode text color and style with a two ascii characters"
import {
  lua     = 'sys:lua',
  ds      = 'civ:lib/ds',
  fd      = 'civ:lib/fd',
  ix      = 'civ:lib/civix',
}

pkg {
  name     = 'asciicolor',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_asciicolor",
  license  = "UNLICENSE",
  doc = 'README.cxt',
}

P.asciicolor = lua {
  mod = 'asciicolor',
  src = { 'asciicolor.lua' },
  dep = {
    ds.ds,
    fd.fd,
    ix.civix,
  },
}

summary"filedescriptor interfaces"
import {
  metaty = 'civ:lib/metaty',
}
pkg {
  name     = 'fd',
  homepage = "https://lua.civboot.org#Package_fd",
  license  = "UNLICENSE",
  version  = '0.1-7',
  url      = 'git+http://github.com/civboot/civlua',
  doc      = 'README.cxt',
}

P.libfd = cc {
  lib = 'fd', -- libfd.so
  hdr = 'fd.h',
  src = 'fd.c',
}

P.fd = lua {
  mod = 'fd',
  src = {
    'fd.lua',
    'fd/IFile.lua',
  },
  lib = P.libfd,
  dep = { metaty },
}

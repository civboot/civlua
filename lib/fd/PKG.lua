summary"filedescriptor interfaces"
import {
  "lua ~> 5.3",
  "metaty ~> 0.1",
}
pkg {
  name     = 'fd',
  homepage = "https://lua.civboot.org#Package_fd",
  license  = "UNLICENSE",
  version  = '0.1-7',
  url      = 'git+http://github.com/civboot/civlua',
  doc      = 'README.cxt',
}

P.fd = lua {
  src = {
    'fd.lua',
    ['fd.sys'] = 'fd.c',
    'fd/IFile.lua',
  },
  lib = {
    ['fd.sys'] = 'fd.so',
  },
}

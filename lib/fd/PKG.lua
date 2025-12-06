local P = {}

P.summary = "filedescriptor interfaces"
local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'fd',
--   homepage = "https://lua.civboot.org#Package_fd",
--   license  = "UNLICENSE",
--   version  = '0.1-7',
--   url      = 'git+http://github.com/civboot/civlua',
--   doc      = 'README.cxt',
-- }

P.libfd = cc {
  lib = 'fd', -- libfd.so
  hdr = 'fd.h',
  src = 'fd.c',
  tag = { builder = 'bootstrap' },
}

P.fd = lua {
  mod = 'fd',
  dep = {
    'civ:lib/fd#libfd',
    'civ:lib/metaty',
    'civ:lib/ds',
  },
  tag = { builder = 'bootstrap' },
}

return P

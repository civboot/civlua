local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

local P = {summary = "filedescriptor interfaces"}

P.libfd = cc {
  lib = 'fd', -- libfd.so
  hdr = 'fd.h',
  src = 'fd.c',
  tag = { builder = 'bootstrap' },
}

-- Note: tests are in lib/tests/
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

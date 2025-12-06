local P = {}
P.summary = "Unix sys library"
local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'civix',
--   homepage = "https://lua.civboot.org#Package_civix",
--   license  = "UNLICENSE",
--   version  = '0.1-8',
--   url      = 'git+http://github.com/civboot/civlua',
--   doc      = 'README.cxt',
-- }

P.civixlib = cc {
  lib = 'civix',
  src = 'civix.c',
  tag = { builder = 'bootstrap', }
}

P.civix = lua {
  mod = 'civix',
  src = {
    'civix.lua',
    'testing.lua',
  },
  lib = 'civ:lib/civix#civixlib',
  dep = {
    'civ:lib/ds',
    'civ:lib/shim',
    'civ:lib/fd',
    'civ:lib/lap',
  },
  tag = { builder = 'bootstrap' },
}

return P

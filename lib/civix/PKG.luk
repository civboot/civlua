local P = {}
P.summary = "Unix sys library"
local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

P.civixlib = cc {
  lib = 'civix',
  src = 'civix.c',
  tag = { builder = 'bootstrap', }
}

-- Note: tests are in lib/tests/
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

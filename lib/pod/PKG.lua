local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'

local P = { summary = "Plain old data (POD) de/serialization" }

P.podlib = cc {
  lib = 'pod',
  src = 'pod.c',
  tag = { builder = 'bootstrap' },
}

-- Note: tests are in lib/tests/
P.pod = lua {
  mod = 'pod',
  src = { 'pod.lua' },
  dep = {
    'civ:lib/metaty',
    'civ:lib/pod#podlib',
  },
  tag = { builder = 'bootstrap' },
}

return P

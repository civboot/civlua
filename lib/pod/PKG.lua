local P = {}
P.summary = "Plain old data (POD) de/serialization"
local cc  = import'sys:cc.luk'
local lua = import'sys:lua.luk'
-- pkg {
--   name     = 'pod',
--   version  = '0.1-3',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_pod",
--   license  = "UNLICENSE",
--   doc      = 'README.cxt',
-- }

P.podlib = cc {
  lib = 'pod',
  src = 'pod.c',
  tag = { builder = 'bootstrap' },
}

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

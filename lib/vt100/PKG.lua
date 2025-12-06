local P = {}
P.summary = "Civboot VT100 Terminal Library"
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'vt100',
--   version  = '0.1-0',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_vt100",
--   license  = "UNLICENSE",
--   doc      = 'README.cxt',
-- }

P.vt100 = lua {
  mod = 'vt100',
  src = {
    'vt100.lua',
    'vt100/AcWriter.lua',
    'vt100/testing.lua',
  },
  dep = {
    'civ:lib/civix',
    'civ:lib/asciicolor',
  },
  tag = { builder = 'bootstrap' },
}

return P

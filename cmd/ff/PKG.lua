local P = {}
P.summary = "find+fix files"
local lua = import'sys:lua.luk'
-- pkg {
--   name    = 'ff',
--   version = '0.1-0',
--   url     = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_ff",
--   license  = "UNLICENSE",
-- }

P.ff = lua {
  mod  = 'ff',
  dep = {
    -- 'civ:lib',
    'civ:lib/civix',
    'civ:lib/vt100',
    'civ:lib/pod',
    'civ:lib/luk',
    'civ:lib/lson',
    'civ:lib/lines',
    'civ:lib/civtest',
  },
  link = {['lua/ff.lua'] = 'bin/ff'},
}

return P

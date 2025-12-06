local P = {}
P.summary = "Lua Asynchronous Protocol and helper library"
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'lap',
--   version  = '0.1-3',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = 'https://lua.civboot.org#Package_lap',
--   license  = 'UNLICENSE',
--   doc      = 'README.cxt',
-- }

P.lap = lua {
  mod = 'lap',
  dep = {
    'civ:lib/ds',
  }
}

return P

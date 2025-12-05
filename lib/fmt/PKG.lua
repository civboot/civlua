local P = {}
P.summary = "format and style anything"
-- pkg {
--   name     = 'fmt',
--   version  = '0.1-0',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = 'https://lua.civboot.org#Package_fmt',
--   license  = 'UNLICENSE',
-- }

local lua = import'sys:lua.luk'

P.fmt = lua {
  mod = 'fmt',
  src = {
    'fmt.lua',
    'binary.lua',
  },
  dep = {
    'civ:lib/metaty metaty',
  },
}

return P

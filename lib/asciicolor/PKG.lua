local P = {}
P.summary = "Tiny data structures and algorithms for lua."
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'asciicolor',
--   version  = '0.1-0',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_asciicolor",
--   license  = "UNLICENSE",
--   doc = 'README.cxt',
-- }

P.asciicolor = lua {
  mod = 'asciicolor',
  dep = {
    'civ:lib/civix',
  },
  tag = { builder = 'bootstrap' },
}

return P

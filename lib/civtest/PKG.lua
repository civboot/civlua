local P = {}
P.summary = "Ultra simple testing library"
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'civtest',
--   version  = '0.1-2',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_civtest",
--   license  = "UNLICENSE",
--   doc = 'README.cxt',
-- }

P.civtest = lua {
  mod = 'civtest',
  src = { 'civtest.lua' },
  dep = {
    'civ:lib/civix',
    'civ:lib/lines',
  },
  tag = { builder = 'bootstrap' },
}

return P

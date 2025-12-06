local P = {}
P.summary = "JSON+ de/serializer in pure lua"
local lua = import'sys:lua.luk'
-- pkg {
--   name     = 'lson',
--   version  = '0.1-0',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_lson",
--   license  = "UNLICENSE",
--   doc      = 'README.cxt',
-- }

P.lson = lua {
  mod = 'lson',
  tag = { builder = 'bootstrap' },
}

return P

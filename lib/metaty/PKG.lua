local P = {}
P.summary = "Simple but effective Lua type system using metatables"
-- pkg {
--   name     = 'metaty',
--   version  = '0.1-15',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = 'https://lua.civboot.org#Package_metaty',
--   license  = 'UNLICENSE',
--   doc      = 'README.cxt',
-- }

local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.metaty = lua{
  'metaty',
  tag = {builder = 'bootstrap'},
}

return P

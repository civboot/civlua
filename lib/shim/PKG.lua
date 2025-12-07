local P = {}
P.summary = "Write scripts for Lua, execute from shell"
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'shim',
--   version  = '0.1-5',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_shim",
--   license  = "UNLICENSE",
--   doc      = 'README.cxt',
-- }

P.shim = lua {
  mod = 'shim',
  dep = { 'civ:lib/fmt' },
  tag = { builder = 'bootstrap' },
}

return P

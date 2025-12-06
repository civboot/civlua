local P = {}

P.summary = "asciicolor syntax highlighting"
local lua = import'sys:lua.luk'

-- pkg {
--   name     = 'acsyntax',
--   version  = '0.1-0',
--   url      = 'git+http://github.com/civboot/civlua',
--   homepage = "https://lua.civboot.org#Package_acsyntax",
--   license  = "UNLICENSE",
--   doc = 'README.cxt',
-- }

P.acsyntax = lua {
  mod = 'acsyntax'
  src = {
    'acsyntax.lua',
  },
  dep = {
    'civ:civix',
    'civ:pegl',
  }
}

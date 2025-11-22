summary'Simple but effective Lua type system using metatables'
import {} -- none

pkg {
  name     = 'metaty',
  version  = '0.1-15',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org#Package_metaty',
  license  = 'UNLICENSE',
  doc      = 'README.cxt',
}

P.metaty = lua {
  src = { 'metaty.lua' }
}

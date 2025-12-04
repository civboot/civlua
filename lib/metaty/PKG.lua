summary'Simple but effective Lua type system using metatables'
import { lua = 'sys:lua' }
pkg {
  name     = 'metaty',
  version  = '0.1-15',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org#Package_metaty',
  license  = 'UNLICENSE',
  doc      = 'README.cxt',
}

P.metaty = lua'metaty'

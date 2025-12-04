summary"write scripts for Lua, execute from shell"
import {
  lua   = 'sys:lua',
}
pkg {
  name     = 'shim',
  version  = '0.1-5',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_shim",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.shim = lua'shim'

summary"PEG-like recursive descent parsing in Lua"
import {
  "lua     ~> 5.3",
  "pkg     ~> 0.1",
  "metaty  ~> 0.1",
  "ds      ~> 0.1",
  "civtest ~> 0.1",
}

pkg {
  name    = 'pegl',
  version = '0.1-2',
  url     = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_pegl",
  doc = 'README.cxt',
}

P.pegl = lua {
  src = {
    'pegl.lua',
    'pegl/lua.lua',
  },
}

summary"asciicolor syntax highlighting"
import {
  "lua    ~> 5.3",
  "ds ~> 0.1", -- only for asciicolor/AcWriter.lua
  "metaty ~> 0.1", -- only for asciicolor/AcWriter.lua
  "asciicolor ~> 0.1", -- only for asciicolor/AcWriter.lua
  "pegl ~> 0.1", -- only for asciicolor/AcWriter.lua
}

pkg {
  name     = 'acsyntax',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_acsyntax",
  license  = "UNLICENSE",
  doc = 'README.cxt',
}

P.acsyntax = lua {
  src = {
    'acsyntax.lua',
  },
}

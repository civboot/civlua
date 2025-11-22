summary"encode text color and style with a two ascii characters"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1", -- only for asciicolor/AcWriter.lua
}

pkg {
  name     = 'asciicolor',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_asciicolor",
  license  = "UNLICENSE",
  doc = 'README.cxt',
}

P.asciicolor = lua {
  src = {
    'asciicolor.lua',
  },
}

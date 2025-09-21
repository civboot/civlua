name     = 'acsyntax'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "asciicolor syntax highlighting"
homepage = "https://lua.civboot.org#Package_acsyntax"
license  = "UNLICENSE"
doc = 'README.cxt'
deps = {
  "lua    ~> 5.3",
  "ds ~> 0.1", -- only for asciicolor/AcWriter.lua
  "metaty ~> 0.1", -- only for asciicolor/AcWriter.lua
  "asciicolor ~> 0.1", -- only for asciicolor/AcWriter.lua
  "pegl ~> 0.1", -- only for asciicolor/AcWriter.lua
}
srcs = {
  'acsyntax.lua',
}


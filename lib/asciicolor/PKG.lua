name     = 'asciicolor'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "encode text color and style with a two ascii characters"
homepage = "https://github.com/civboot/civlua/blob/main/lib/asciicolor/README.md"
license  = "UNLICENSE"
doc = 'README.cxt'
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1", -- only for asciicolor/AcWriter.lua
}
srcs = {
  'asciicolor.lua',
  'asciicolor/style.lua',
}



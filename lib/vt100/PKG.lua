name     = 'vt100'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Civboot VT100 Terminal Library"
homepage = "https://lua.civboot.org#Package_vt100"
license  = "UNLICENSE"
doc      = 'README.cxt'
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
  "asciicolor ~> 0.1",

  -- vt100.testing.run also requires: lap, civix, fd
}
srcs = {
  'vt100.lua',
  'vt100/AcWriter.lua',
  'vt100/testing.lua',
}



name     = 'civtest'
version  = '0.1-2'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Ultra simple testing library"
homepage = "https://lua.civboot.org#Package_civtest"
license  = "UNLICENSE"
doc = 'README.cxt'
srcs = { 'civtest.lua' }
deps = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}

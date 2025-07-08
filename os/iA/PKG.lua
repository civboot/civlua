name     = 'iA'
version  = '0.1-13'
url      = 'git+http://github.com/civboot/civlua'
summary  = "intermediate Assembly programming language"
homepage = "https://lua.civboot.org#Package_iA"
license  = "UNLICENSE"
doc      = 'README.cxt'
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1",
}
srcs = {
  'iA.lua',
}


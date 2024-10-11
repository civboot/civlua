name     = 'fmt'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "format lua types"
homepage = "https://lua.civboot.org#Package_fmt"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
}
srcs = {
  'fmt.lua',
  ['fmt.binary'] = 'binary.lua',
}


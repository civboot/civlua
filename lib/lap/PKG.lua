name     = 'lap'
version  = '0.1-3'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Lua Asynchronous Protocol and helper library"
homepage = "https://lua.civboot.org#Package_lap"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1",
  "ds     ~> 0.1",
}
srcs = {
  'lap.lua',
}


name     = 'ds'
version  = '0.1-10'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Tiny data structures and algorithms"
homepage = "https://github.com/civboot/civlua/blob/main/lib/ds/README.md"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
}
srcs = {
  'ds.lua',
  'ds/lines.lua',
  'ds/heap.lua',
  'ds/file.lua',
  'ds/log.lua',
  'ds/testing.lua',
}

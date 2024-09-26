name     = 'ds'
version  = '0.1-12'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Tiny data structures and algorithms"
homepage = "https://github.com/civboot/civlua/blob/main/lib/ds/README.md"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1",
}
srcs = {
  'ds.lua',
  'ds/Iter.lua',
  'ds/pod.lua',
  'ds/LL.lua',
  'ds/path.lua',
  'ds/utf8.lua',
  'ds/heap.lua',
  'ds/log.lua',
  'ds/Grid.lua',
}

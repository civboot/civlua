name     = 'ds'
version  = '0.1-5'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Tiny data structures and algorithms"
homepage = "https://github.com/civboot/civlua/blob/main/lib/ds/README.md"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "metaty ~> 0.1",
}
srcs = {
  'ds.lua',
  'ds/heap.lua',
  'ds/file.lua',
  'ds/diff.lua',
}

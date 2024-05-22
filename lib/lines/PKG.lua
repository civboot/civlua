name     = 'lines'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Data structures for mixed media (memory/fs) lines of text"
homepage = "https://github.com/civboot/civlua/blob/main/lib/lines/README.md"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}
srcs = {
  'lines.lua',
  'lines/Gap.lua',
  'lines/testing.lua',
}


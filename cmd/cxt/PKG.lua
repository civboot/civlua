name    = 'cxt'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
summary  = "text markup for civilization"
doc      = 'README.cxt'
homepage = "https://lua.civboot.org#Package_cxt"
license  = "UNLICENSE"
srcs = {
  'cxt.lua',
  'cxt/term.lua',
  'cxt/html.lua',
}
deps = {
  "lua     ~> 5.3",
  "pkg     ~> 0.1",
  "civtest ~> 0.1",
  "ds      ~> 0.1",
  "pegl    ~> 0.1",
  "metaty  ~> 0.1",
  "shim    ~> 0.1",
}

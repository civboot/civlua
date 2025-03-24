name     = 'civix'
summary  = "Unix sys library"
homepage = "https://lua.civboot.org#Package_civix"
license  = "UNLICENSE"
version  = '0.1-8'
url      = 'git+http://github.com/civboot/civlua'
doc      = 'README.cxt'
srcs = {
  'civix.lua',
  ['civix.lib'] = 'civix/lib.c',
  'civix/testing.lua',
}
libs = {
  ['civix.lib'] = 'civix/lib.so',
}
deps = {
  "lua ~> 5.3",
  "shim   ~> 0.1",
  "fd     ~> 0.1",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
  "lap    ~> 0.1",
}

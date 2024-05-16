name     = 'civix'
summary  = "Simple but effective Lua type system using metatables"
homepage = "https://github.com/civboot/civlua/blob/main/lib/civix/README.md"
license  = "UNLICENSE"
version  = '0.1-7'
url      = 'git+http://github.com/civboot/civlua'
srcs = {
  'civix.lua',
  'civix/term.lua',
  ['civix.lib'] = 'civix/lib.c',
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

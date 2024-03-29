name     = 'civix'
summary  = "Simple but effective Lua type system using metatables"
homepage = "https://github.com/civboot/civlua/blob/main/lib/civix/README.md"
license  = "UNLICENSE"
version  = '0.1-2'
url      = 'git+http://github.com/civboot/civlua'
srcs = {
  'civix.lua',
  'civix/term.lua',
}
libs = {
  ['civix.lib'] = 'civix/lib.so',
}
deps = {
  "lua ~> 5.3",
  "metaty ~> 0.1",
  "ds ~> 0.1",
  "luaposix ~> 36.2", -- TODO: would be good to find the minimum version
}

name     = 'smol'
summary  = "compression algorithms"
homepage = "https://lua.civboot.org#Package_smol"
license  = "UNLICENSE"
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
doc = 'README.cxt'
srcs = {
  'smol.lua',
  ['smol.sys'] = 'smol.c',
}
libs = {
  ['smol.sys'] = 'smol.so',
}
deps = {
  "lua ~> 5.3",
}


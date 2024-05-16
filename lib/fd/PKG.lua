name     = 'fd'
summary  = "filedescriptor interfaces"
homepage = "https://github.com/civboot/civlua/blob/main/lib/fd/README.md"
license  = "UNLICENSE"
version  = '0.1-6'
url      = 'git+http://github.com/civboot/civlua'
srcs = {
  'fd.lua',
  ['fd.sys'] = 'fd.c',
}
libs = {
  ['fd.sys'] = 'fd.so',
}
deps = {
  "lua ~> 5.3",
}

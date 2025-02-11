name     = 'fd'
summary  = "filedescriptor interfaces"
homepage = "https://lua.civboot.org#Package_fd"
license  = "UNLICENSE"
version  = '0.1-7'
url      = 'git+http://github.com/civboot/civlua'
doc = 'README.cxt'
srcs = {
  'fd.lua',
  ['fd.sys'] = 'fd.c',
  'fd/IFile.lua',
}
libs = {
  ['fd.sys'] = 'fd.so',
}
deps = {
  "lua ~> 5.3",
  "metaty ~> 0.1",
}

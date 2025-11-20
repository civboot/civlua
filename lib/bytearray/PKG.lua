name     = 'bytearray'
summary  = "lua bytearray type."
homepage = "https://lua.civboot.org#Package_bytearray"
license  = "UNLICENSE"
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
doc = 'README.cxt'
srcs = {
  ['bytearrray'] = 'bytearray.c',
}
libs = {
  ['bytearray'] = 'libbytearray.so',
}
deps = {
  "lua ~> 5.3",
}


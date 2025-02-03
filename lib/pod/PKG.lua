name     = 'pod'
version  = '0.1-2'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Plain old data (POD) de/serialization"
homepage = "https://lua.civboot.org#Package_pod"
license  = "UNLICENSE"
doc      = 'README.cxt'
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
}
srcs = {
  'pod.lua',
  ['pod.native'] = 'pod.c',
  'pod/testing.lua',
}
libs = {
  ['pod.native'] = 'pod.so',
}

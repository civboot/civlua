summary"Plain old data (POD) de/serialization"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
}

pkg {
  name     = 'pod',
  version  = '0.1-3',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_pod",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.pod = lua {
  src = {
    'pod.lua',
    ['pod.native'] = 'pod.c',
    'pod/testing.lua',
  },
  lib = {
    ['pod.native'] = 'pod.so',
  },
}

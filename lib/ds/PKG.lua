summary"Tiny data structures and algorithms"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "fmt    ~> 0.1",
}

pkg {
  name     = 'ds',
  version  = '0.1-13',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_ds",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.ds = lua {
  src = {
    'ds.lua',
    'ds/Iter.lua',
    'ds/LL.lua',
    'ds/path.lua',
    'ds/utf8.lua',
    'ds/heap.lua',
    'ds/log.lua',
    'ds/Grid.lua',
    'ds/kev.lua',
    'ds/testing.lua',
    ['ds.lib'] = {'ds.c', 'ds.h'},
  },
  lib = {
    ['ds.lib'] = 'libds.so',
  },
}

summary"find+fix files"
import {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "shim   ~> 0.1",
}

pkg {
  name    = 'ff',
  version = '0.1-0',
  url     = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_ff",
  license  = "UNLICENSE",
}

P.ff = lua {
  src  = { 'ff.lua' },
  main = 'ff.Main',
}

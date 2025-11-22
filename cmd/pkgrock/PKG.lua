summary"pkg utilities to work with rockspecs"
import {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "shim   ~> 0.1",
}

pkg {
  name    = 'pkgrock',
  version = '0.1-1',
  url     = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_pkgrock",
  license  = "UNLICENSE",
}

P.pkgrock = lua {
  src = {'pkgrock.lua'},
}

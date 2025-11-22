summary"Luck config language"
import {
  "lua     ~> 5.3",
  "pkg     ~> 0.1",
  "metaty  ~> 0.1",
  "ds      ~> 0.1",
  "pegl    ~> 0.1",
}

pkg {
  name    = 'luck',
  version = '0.1-0',
  url     = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_luck",
  doc = 'README.cxt',
}

P.luck = lua {
  src = { 'luck.lua' }
}

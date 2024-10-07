name    = 'pkgrock'
version = '0.1-1'
url     = 'git+http://github.com/civboot/civlua'
summary  = "pkg utilities to work with rockspecs"
homepage = "https://lua.civboot.org#Package_pkgrock"
license  = "UNLICENSE"
srcs = {'pkgrock.lua'}
deps = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "shim   ~> 0.1",
}

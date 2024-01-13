name    = 'pkgrock'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
summary  = "pkg utilities to work with rockspecs"
homepage = "https://github.com/civboot/civlua/blob/main/cmd/pkgrock/README.md"
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

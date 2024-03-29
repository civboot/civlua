name     = 'flux'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "simple change management software"
homepage = "https://github.com/civboot/civlua/blob/main/cmd/flux/README.md"
license  = "UNLICENSE"
srcs    = { 'flux.lua' }
deps = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "vcds   ~> 0.1",
  "shim   ~> 0.1",
  "patience ~> 0.1",
}

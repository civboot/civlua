name    = 'ff'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
summary  = "find+fix files"
homepage = "https://github.com/civboot/civlua/blob/main/cmd/ff/README.md"
license  = "UNLICENSE"
srcs     = { 'ff.lua' }
main     = 'ff.Main'
deps = {
  "lua    ~> 5.3",
  "pkg    ~> 0.1",
  "civix  ~> 0.1",
  "ds     ~> 0.1",
  "metaty ~> 0.1",
  "shim   ~> 0.1",
}

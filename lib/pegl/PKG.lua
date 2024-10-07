name    = 'pegl'
version = '0.1-2'
summary  = "PEG-like recursive descent parsing in Lua"
url     = 'git+http://github.com/civboot/civlua'
doc = 'README.cxt'
srcs = {
  'pegl.lua',
  'pegl/lua.lua',
}
deps = {
  "lua     ~> 5.3",
  "pkg     ~> 0.1",
  "metaty  ~> 0.1",
  "ds      ~> 0.1",
  "civtest ~> 0.1",
}

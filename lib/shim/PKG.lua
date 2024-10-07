name     = 'shim'
version  = '0.1-5'
url      = 'git+http://github.com/civboot/civlua'
summary  = "write scripts for Lua, execute from shell"
homepage = "https://lua.civboot.org#Package_shim"
license  = "UNLICENSE"
doc      = 'README.cxt'
srcs = { 'shim.lua' }
deps = {
  "lua ~> 5.3",

  -- OPTIONAL: needed for setup() and checkHelp()
  -- doc ~> "0.1",
}

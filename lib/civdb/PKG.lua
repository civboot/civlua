name     = 'civdb'
summary  = "minimalistic CRUD database"
homepage = "https://lua.civboot.org#Package_civdb"
license  = "UNLICENSE"
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
doc = 'README.cxt'
srcs = {
  'civdb.lua',
  ['civdb.sys'] = 'civdb.c',
  'civdb/RowFile.lua',
  'civdb/CivDB.lua',
}
libs = {
  ['civdb.sys'] = 'civdb.so',
}
deps = {
  "lua ~> 5.3",
}


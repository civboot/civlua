-- Note: this is only for demonstration and working with the pkgrock utility.
-- Obviously you cannot import pkg using pkg (you must require'pkglib')

name     = 'pkg'
version  = '0.1-15'
url      = 'git+http://github.com/civboot/civlua'
summary  = "local and recursive require"
homepage = "https://github.com/civboot/civlua/blob/main/lib/pkg/README.md"
license  = "UNLICENSE"
doc      = 'README.cxt'
srcs = {
  'pkglib.lua',
}
deps = {
  "lua ~> 5.3",
}

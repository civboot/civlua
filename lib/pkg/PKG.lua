-- Note: this is only for demonstration and working with the pkgrock utility.
-- Obviously you cannot import pkg using pkg (you must require'pkglib')

name     = 'pkg'
version  = '0.1-2'
url      = 'git+http://github.com/civboot/civlua'
summary  = "better lua package creation and importing"
homepage = "https://github.com/civboot/civlua/blob/main/lib/pkg/README.md"
license  = "UNLICENSE"
srcs = {
  'pkglib.lua',
}
deps = {
  "lua ~> 5.3",
}

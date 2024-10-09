name     = 'lines'
version  = '0.1-0'
url      = 'git+http://github.com/civboot/civlua'
summary  = "Data structures for mixed media (memory/fs) lines of text"
homepage = "https://lua.civboot.org#Package_lines"
license  = "UNLICENSE"
deps = {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}
srcs = {
  'lines.lua',
  'lines/diff.lua',
  'lines/Writer.lua',
  'lines/Gap.lua',
  'lines/U3File.lua',
  'lines/File.lua',
  'lines/EdFile.lua',
  'lines/testing.lua',
}


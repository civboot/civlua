summary"Data structures for mixed media (memory/fs) lines of text"
import {
  "lua    ~> 5.3",
  "metaty ~> 0.1",
  "ds     ~> 0.1",
}

local P = pkg {
  name     = 'lines',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_lines",
  license  = "UNLICENSE",
}

P.lua = lua {
  src = {
    'lines.lua',
    'lines/diff.lua',
    'lines/Writer.lua',
    'lines/Gap.lua',
    'lines/U3File.lua',
    'lines/File.lua',
    'lines/EdFile.lua',
    'lines/testing.lua',
    'lines/futils.lua',
    'lines/motion.lua',
    'lines/buffer.lua',
  },
}

return P

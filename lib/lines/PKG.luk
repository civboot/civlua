local P = {}
P.summary = "Data structures for mixed media (memory/fs) lines of text"
local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.lines = lua {
  mod = 'lines',
  src = {
    'lines.lua',
    'diff.lua',
    'Writer.lua',
    'Gap.lua',
    'U3File.lua',
    'File.lua',
    'EdFile.lua',
    'futils.lua',
    'motion.lua',
    'buffer.lua',
    'kev.lua',
  },
  dep = {
    'civ:lib/civix',
  },
  tag = { builder = 'bootstrap' },
}

return P

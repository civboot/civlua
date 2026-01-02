local P = {}
P.summary = "Data structures for mixed media (memory/fs) lines of text"
local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.lines = lua {
  mod = 'lines',
  src = {
    'lines.lua',
    'lines/diff.lua',
    'lines/Writer.lua',
    'lines/Gap.lua',
    'lines/U3File.lua',
    'lines/File.lua',
    'lines/EdFile.lua',
    'lines/futils.lua',
    'lines/motion.lua',
    'lines/buffer.lua',
  },
  dep = {
    'civ:lib/civix',
  },
  tag = { builder = 'bootstrap' },
}

return P

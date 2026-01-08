local lua = import'sys:lua.luk'

local P = { summary = "Civboot VT100 Terminal Library" }

-- Note: tests are in lib/tests/
P.vt100 = lua {
  mod = 'vt100',
  src = {
    'vt100.lua',
    'AcWriter.lua',
    'testing.lua',
  },
  dep = {
    'civ:lib/civix',
    'civ:lib/asciicolor',
  },
  tag = { builder = 'bootstrap' },
}

return P

local P = {}
P.summary = "Ultra simple testing library"
local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.civtest = lua {
  mod = 'civtest',
  src = { 'civtest.lua' },
  dep = {
    'civ:lib/civix',
    'civ:lib/lines',
  },
  tag = { builder = 'bootstrap' },
}

return P

local P = {}

local lua = import'sys:lua.luk'

P.testing = lua {
  mod = 'lines',
  src = { 'testing.lua' },
  dep = {
    'civ:lib/civix',
    'civ:lib/civtest',
  }
}

return P

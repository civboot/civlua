local P = {}

local lua = import'sys:lua.luk'

P.testing = lua{
  mod = 'ds',
  src = { 'testing.lua' },
  dep = {
    'civ:lib/ds',
    'civ:lib/civtest',
  },
}

return P

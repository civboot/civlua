local lua = import'sys:lua.luk'

local P = {}
P.summary = "PEG-like recursive descent parsing in Lua"

P.pegl = lua {
  mod = 'pegl',
  src = {
    'pegl.lua',
    'lua.lua',
  },
  dep = {
    'civ:lib/ds',
    'civ:lib/lines',
    'civ:lib/civtest',
  },
}

P.test = lua.test {
  src = {
    'test_pegl.lua',
    'test_lua.lua',
  },
  dep = { 'civ:lib/pegl' },
}

return P

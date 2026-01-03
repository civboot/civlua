local lua = import'sys:lua.luk'

local P = { summary = "luk: lua config language." }

P.luk = lua {
  mod = 'luk',
  dep = {
    'civ:lib/ds',
  },
  tag = { builder = 'bootstrap' },
}

return P

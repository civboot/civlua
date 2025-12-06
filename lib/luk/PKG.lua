local P = {}
P.summary = "luk: lua config language."
local lua = import'sys:lua.luk'

P.luk = lua {
  mod = 'luk',
  dep = {
    'civ:lib/ds',
  },
  tag = { builder = 'bootstrap' },
}

return P

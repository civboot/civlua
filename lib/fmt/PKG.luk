local lua = import'sys:lua.luk'

local P = { summary = "format and style anything" }

-- Note: tests are in lib/tests/
P.fmt = lua {
  mod = 'fmt',
  src = {
    'fmt.lua',
    'binary.lua',
  },
  dep = {
    'civ:lib/metaty',
  },
  tag = { builder = 'bootstrap' },
}

return P

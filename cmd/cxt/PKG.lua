local lua = import'sys:lua.luk'

local P = { summary = "text markup for civilization" }

P.cxt = lua {
  mod = 'cxt',
  src = {
    'cxt.lua',
    'term.lua',
    'html.lua',
  },
  dep = { "civ:lib" },
}

P.test = lua.test {
  src = 'test.lua',
  dep = { 'civ:cmd/cxt' },
}

return P

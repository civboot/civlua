local lua = import'sys:lua.luk'

local P = { summary = "Print and export documentation." }

P.doc = lua {
  mod = 'doc',
  src = {
    'doc.lua',
    'lua.lua',
  },
  dep = {
    "civ:lib",
    "civ:cmd/cxt",
  },
}

P.test = lua.test {
  src = 'test.lua',
  dep = { 'civ:cmd/doc' },
}

return P

local lua = import'sys:lua.luk'
local doc = import'civ:doc.luk'

local P = { summary = "Simple version control software" }

P.pvc = lua {
  mod = 'pvc',
  src = {
    'pvc.lua',
    'unix.lua'
  },
  dep = { 'civ:lib' },
}

P.test = lua.test {
  src = 'test.lua',
  dep = {
    'civ:cmd/pvc',
  },
}

P.doc_pvc = doc.lua {
  mod = 'pvc',
  src = 'README.cxt',
  lua = { 'civ:cmd/pvc' },
}

return P

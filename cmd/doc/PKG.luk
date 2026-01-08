local lua = import'sys:lua.luk'
local doc = import'civ:doc.luk'

local P = { summary = "Print and export documentation." }

P.doc = lua {
  mod = 'doc',
  src = {
    'doc.lua',
    'lua.lua',
  },
  dep = {
    "civ:lib/lines",
    "civ:lib/civtest",
    "civ:lib/pegl",
    "civ:cmd/cxt",
  },
  tag = { builder = 'bootstrap' },
  link = {['lua/doc.lua'] = 'bin/luadoc'},
}

P.test = lua.test {
  src = 'test.lua',
  dep = { 'civ:cmd/doc' },
}

P.doc_doc = doc.lua {
  mod = 'doc',
  src = 'README.cxt',
  lua = { 'civ:cmd/doc' },
}

return P

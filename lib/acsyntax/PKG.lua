local lua = import'sys:lua.luk'

local P = {}
P.summary = "asciicolor syntax highlighting"

P.acsyntax = lua {
  mod = 'acsyntax',
  dep = {
    'civ:lib/civix',
    'civ:lib/pegl',
  }
}

P.test = lua.test {
  src = 'test.lua',
  dep = { 'civ:lib/acsyntax' },
}

return P

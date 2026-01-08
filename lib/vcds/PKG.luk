local lua = import'sys:lua.luk'

local P = { summary = "version control data structures and algorithms" }

P.vcds = lua {
  mod = 'vcds',
  dep = { 'civ:lib/ds' },
}

P.test = lua.test {
  src = 'test.lua',
  dep = { 'civ:lib/vcds' },
}

return P

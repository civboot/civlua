local P = {}
P.summary = "Write scripts for Lua, execute from shell"
local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.shim = lua {
  mod = 'shim',
  dep = { 'civ:lib/metaty' },
  tag = { builder = 'bootstrap' },
}

return P

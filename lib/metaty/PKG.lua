local P = { summary = "Simple but effective Lua type system using metatables" }

local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.metaty = lua{
  'metaty',
  tag = {builder = 'bootstrap'},
}

return P

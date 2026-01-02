local P = {}
P.summary = "JSON+ de/serializer in pure lua"
local lua = import'sys:lua.luk'

-- Note: tests are in lib/tests/
P.lson = lua {
  mod = 'lson',
  tag = { builder = 'bootstrap' },
}

return P

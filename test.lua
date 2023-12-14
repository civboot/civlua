METATY_CHECK = true
METATY_DOC   = true

local civ = dofile'civ.lua'
local T, dir = require'civtest', civ.dir

T.test('[[core]]', function()
  os.execute('LUA_PATH=?/?.lua lua shim/test.lua --test=test.lua')
  dofile(dir..'metaty/test.lua')
  dofile(dir..'ds/test.lua')
  dofile(dir..'civtest/test.lua')
  dofile(dir..'doc/test.lua')
  dofile(dir..'smol/test.lua')
end)

T.test('[[libs]]', function()
  dofile(dir..'pegl/tests/test_pegl.lua')
  dofile(dir..'pegl/tests/test_lua.lua')
  dofile(dir..'rebuf/tests/test_motion.lua')
  dofile(dir..'rebuf/tests/test_gap.lua')
  dofile(dir..'rebuf/tests/test_buffer.lua')
  dofile(dir..'civix/test.lua')
  dofile(dir..'civix/test_term.lua')
  dofile(dir..'patience/test.lua')
end)

T.test('[[apps]]', function()
  dofile(dir..'ff/test.lua')
end)

T.test('[[ele]]', function()
  dofile(dir..'ele/tests/test_action.lua')
  dofile(dir..'ele/tests/test_model.lua')
end)

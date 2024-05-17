METATY_CHECK = true
METATY_DOC   = true

local civ = dofile'civ.lua'
local pkg = require
local T = require'civtest'
local dir = ''

print'[[core]]'
  assert(os.execute[[
    lua -e "require'pkglib'.install()" lib/shim/test.lua --test=test.lua
  ]])
  dofile(dir..'lib/fd/test.lua')
  dofile(dir..'lib/metaty/test.lua')
  dofile(dir..'lib/ds/test.lua')
  dofile(dir..'lib/lap/test.lua')
  dofile(dir..'lib/vcds/test.lua')
  dofile(dir..'lib/civtest/test.lua')
  dofile(dir..'lib/doc/test.lua')

print'[[libs]]'
  dofile(dir..'lib/pegl/tests/test_pegl.lua')
  dofile(dir..'lib/pegl/tests/test_lua.lua')
  dofile(dir..'lib/tso/test.lua')
  dofile(dir..'lib/luck/test.lua')
  dofile(dir..'cmd/cxt/tests/test_cxt.lua')
  dofile(dir..'lib/rebuf/tests/test_motion.lua')
  dofile(dir..'lib/rebuf/tests/test_gap.lua')
  dofile(dir..'lib/rebuf/tests/test_buffer.lua')
  dofile(dir..'lib/civix/test.lua')
  dofile(dir..'lib/civix/test_term.lua')
  dofile(dir..'lib/patience/test.lua')

print'[[apps]]'
  dofile(dir..'cmd/ff/test.lua')

print'[[ele]]'
  dofile(dir..'cmd/ele/tests/test_term.lua')

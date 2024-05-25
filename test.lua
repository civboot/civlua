DOC, METATY_CHECK              = false, true
LAP_READY,    LAP_ASYNC        = false, false
LAP_FNS_SYNC, LAP_FNS_ASYNC    = false, false

-- for early tests / libs to log
LOGLEVEL = tonumber(os.getenv'LOGLEVEL') or 0
LOGFN = function(lvl, msg) if LOGLEVEL >= lvl then
  io.stderr:write(string.format('LOG(%s): %s\n', lvl, msg))
end end

local dir = '' -- leave here incase support is needed for filedir

local tests = os.getenv'tests' -- do these first
if tests then
  for tpath in tests:gmatch'%S+' do dofile(dir..tpath) end
end

print'[[core]]'
  dofile(dir..'lib/metaty/test.lua')
  dofile(dir..'lib/civtest/test.lua')
  assert(os.execute[[
    lua -e "require'pkglib'.install()" lib/shim/test.lua --test=test.lua
  ]])

  local log = require'ds.log'

  LOGFN = log.logFn; log.setLevel()
  dofile(dir..'lib/ds/test.lua')
  dofile(dir..'lib/lines/test.lua')
  dofile(dir..'lib/lson/test.lua')
  dofile(dir..'lib/tv/test.lua')
  dofile(dir..'lib/fd/test.lua')
  dofile(dir..'lib/lap/test.lua')
  dofile(dir..'lib/vcds/test.lua')
  dofile(dir..'lib/doc/test.lua')

print'[[libs]]'
  dofile(dir..'lib/pegl/tests/test_pegl.lua')
  dofile(dir..'lib/pegl/tests/test_lua.lua')
  dofile(dir..'lib/luck/test.lua')
  dofile(dir..'cmd/cxt/test.lua')
  dofile(dir..'lib/rebuf/tests/test_motion.lua')
  dofile(dir..'lib/rebuf/tests/test_buffer.lua')
  dofile(dir..'lib/civix/test.lua')
  dofile(dir..'lib/patience/test.lua')

print'[[experiment]]'
  dofile(dir..'experiment/tso/test.lua')

print'[[apps]]'
  dofile(dir..'cmd/ff/test.lua')

print'[[ele]]'
  dofile(dir..'cmd/ele/tests/test_term.lua')


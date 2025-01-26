local G = G or _G
G.MAIN = {}

-- for early tests / libs to log
G.LOGLEVEL = tonumber(os.getenv'LOGLEVEL') or 4
G.LOGFN = function(lvl, msg) if LOGLEVEL >= lvl then
  io.stderr:write(string.format('LOG(%s): %s\n', lvl, msg))
end end

local io_open = io.open

local dir = '' -- leave here incase support is needed for filedir

print'[[core]]'
  dofile(dir..'lib/metaty/test.lua')
  require'civ'.setupFmt()
  dofile(dir..'lib/fmt/test.lua')
  dofile(dir..'lib/civtest/test.lua')

  local log = require'ds.log'
  LOGFN = log.logFn; log.setLevel()
  local tests = os.getenv'tests' -- do these first
  if tests then
    for tpath in tests:gmatch'%S+' do dofile(dir..tpath) end
  end

  dofile(dir..'lib/shim/test.lua')
  dofile(dir..'lib/ds/test.lua')
  dofile(dir..'lib/lines/test_diff.lua')
  dofile(dir..'lib/lines/test.lua')
  assert(io_open == io.open)
  dofile(dir..'lib/lines/test_file.lua')
  dofile(dir..'lib/lap/test.lua')
  dofile(dir..'lib/fd/test.lua')

print'[[libs]]'
  dofile(dir..'lib/asciicolor/test.lua')
  dofile(dir..'lib/vt100/test.lua')
  dofile(dir..'lib/lson/test.lua')
  dofile(dir..'lib/vcds/test.lua')
  dofile(dir..'lib/pegl/tests/test_pegl.lua')
  dofile(dir..'lib/pegl/tests/test_lua.lua')
  dofile(dir..'lib/luck/test.lua')
  dofile(dir..'lib/rebuf/tests/test_motion.lua')
  dofile(dir..'lib/rebuf/tests/test_buffer.lua')
  dofile(dir..'lib/civix/test.lua')
  dofile(dir..'lib/civdb/test.lua')
  dofile(dir..'lib/smol/test.lua')

print'[[apps]]'
  dofile(dir..'cmd/doc/test.lua')
  dofile(dir..'cmd/cxt/test.lua')
  dofile(dir..'cmd/ff/test.lua')

print'[[ele]]'
  dofile(dir..'cmd/ele/tests/test_term.lua')
  dofile(dir..'cmd/ele/tests/test_bindings.lua')
  dofile(dir..'cmd/ele/tests/test_actions.lua')
  dofile(dir..'cmd/ele/tests/test_session.lua')


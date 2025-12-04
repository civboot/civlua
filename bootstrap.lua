-- This script bootstrapps civ.lua.
-- Run this to test and build the initial civ command.
local sfmt    = string.format
local io_open = io.open

local src = debug.getinfo(1).source
local D = src:match'@?(.*)bootstrap%.lua$'
print(sfmt('bootstrap.lua in dir %q', D))
assert(not os.execute'ls lua*.core', 'lua.*core file found!!')

MAIN = {}
METATY_CHECK = true
NOLIB = true

local function preload(name, path)
  package.loaded[name] = dofile(D..path)
end

LOGLEVEL = tonumber(os.getenv'LOGLEVEL') or 4
LOGFN = function(lvl, msg) if LOGLEVEL >= lvl then
  io.stderr:write(sfmt('LOG(%s): %s\n', lvl, msg))
end end

print'[[load]]'
  preload('metaty', 'lib/metaty/metaty.lua')
  require'metaty'.setup()
  dofile(D..'lib/metaty/test.lua')

  -- needed for civtest and related tests
  preload('shim', 'lib/shim/shim.lua')
  preload('fmt', 'lib/fmt/fmt.lua')
    preload('fmt.binary', 'lib/fmt/binary.lua')
  preload('ds', 'lib/ds/ds.lua')
    preload('ds.heap', 'lib/ds/ds/heap.lua')
    preload('ds.path', 'lib/ds/ds/path.lua')
    preload('ds.log',  'lib/ds/ds/log.lua')
    preload('ds.load', 'lib/ds/ds/load.lua')
    preload('ds.Iter', 'lib/ds/ds/Iter.lua')
    preload('ds.Grid', 'lib/ds/ds/Grid.lua')
    -- TODO: move out of ds/test.lua
    preload('ds.utf8', 'lib/ds/ds/utf8.lua')
    preload('ds.LL', 'lib/ds/ds/LL.lua')
  preload('lap', 'lib/lap/lap.lua')
  preload('pod', 'lib/pod/pod.lua')
  preload('civix', 'lib/civix/civix.lua')
  preload('lines', 'lib/lines/lines.lua')
    -- TODO: move lines.load/dump to ds.lua
    preload('lines.diff', 'lib/lines/lines/diff.lua')
    -- TODO: move out of lines/test.lua
    preload('lines.Gap', 'lib/lines/lines/Gap.lua')
    preload('lines.Writer', 'lib/lines/lines/Writer.lua')
  preload('civtest', 'lib/civtest/civtest.lua')
  preload('asciicolor', 'lib/asciicolor/asciicolor.lua')
  preload('vt100', 'lib/vt100/vt100.lua')
  preload('vt100.AcWriter', 'lib/vt100/vt100/AcWriter.lua')
  preload('civ.core', 'core.lua')

  -- Additional
  preload('lson', 'lib/lson/lson.lua')
  preload('ds.testing', 'lib/ds/testing/testing.lua')
  preload('pod.testing', 'lib/pod/testing/testing.lua')
  preload('lines.testing', 'lib/lines/testing/testing.lua')

print'[[test]]'
  -- setup and run tests
  require'asciicolor'.setup()
  dofile(D..'lib/fmt/test.lua')
  dofile(D..'lib/civtest/test.lua')

  local log = require'ds.log'
  LOGFN = log.logFn; log.setLevel()

  dofile(D..'lib/shim/test.lua')
  dofile(D..'lib/ds/test.lua')
  dofile(D..'lib/lines/test_diff.lua')
  dofile(D..'lib/lap/test.lua')
  dofile(D..'lib/pod/test.lua')
  dofile(D..'lib/civix/test.lua')

  dofile(D..'lib/lines/test.lua')
  dofile(D..'lib/asciicolor/test.lua')
  dofile(D..'lib/vt100/test.lua')
  -- dofile(D..'lib/lson/test.lua')
  -- dofile(dir..'lib/luck/test.lua')

io.fmt:styled('notify', 'Tests done, running civ.lua', '\n')
require'fmt'.print('args:', arg)

local core = require'civ.core'
local Civ_call = getmetatable(core.Civ).__call 

--- The bootstrapped sys:lua Pkg
local luaPkg = core.Pkg { pkgname = 'sys:lua' }
rawset(luaPkg, 'call', function(self, l)
  return core.Lua(l):target()
end)
rawset(luaPkg, 'test', function(self, t)
  return core.LuaTest(t):target()
end)

--- The bootstrapped sys:lua Pkg
local ccPkg = core.Pkg { pkgname = 'sys:cc' }
rawset(ccPkg, 'call', function(self, cc)
  return core.CC(cc):target()
end)

getmetatable(core.Civ).__call = function(T, t)
  t = Civ_call(T, t)
  t.pkgs['sys:lua'] = luaPkg
  t.pkgs['sys:cc']  = ccPkg
  t.imports['sys:lua'] = {}
  t.imports['sys:cc']  = {}
  return t
end

G.BOOTSTRAP = true
if arg[1] == 'testself' then
  preload('civ', 'civ.lua')
  dofile(D..'test_civ.lua')
  print('Test complete')
  return
end

G.MAIN = nil
dofile(D..'civ.lua')

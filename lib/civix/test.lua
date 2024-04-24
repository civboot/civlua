METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local test, assertEq; pkg.auto'civtest'
local fd = pkg'fd'

local civix  = pkg'civix'
local lib = pkg'civix.lib'
local D = 'lib/civix/'
local push = table.insert

test('sh', function()
  local sh = civix.sh
  local rc, o, l = sh'false'; assertEq(1, rc)
    assertEq('', o)

  rc, o, l = sh'true'; assertEq(0, rc)
    assertEq('', o)

  rc, o, l = sh{'echo', 'hi there'}; assertEq(0, rc)
    assertEq('hi there\n', o)

  print'#### test CAT'
  rc, o, l = sh('cat', 'from stdin'); assertEq(0, rc)
    assertEq('from stdin', o);

  rc, o, l = sh{'commandDoesNotExist', 'blah', 'blah'};
    assert(rc ~= 0);

  rc, o, l = sh{'echo', 'foo', '--abc=ya', aa='bar', bb=42}; assertEq(0, rc)
    assertEq('foo --abc=ya --aa=bar --bb=42\n', o)
  collectgarbage()
end)

test('time', function()
  local period, e1 = ds.Duration(0.001), civix.epoch()
  for i=1,10 do
    civix.sleep(period)
    local e2 = civix.epoch()
    local result = e2 - e1; assert((e2 - e1) > period, result)
    e1 = e2
  end
  civix.sleep(-2.3)
  local m = civix.mono(); civix.sleep(0.001); assert(m < civix.mono())
end)

local function mkTestTree()
  local d = '.out/civix/'
  if civix.exists(d) then civix.rmRecursive(d, true) end
  civix.mkTree(d, {
    ['a.txt'] = 'for civix a test',
    b = {
      ['b1.txt'] = '1 in dir b/',
      ['b2.txt'] = '2 in dir b/',
    },
  }, true)
  return d
end

test('mkTree', function()
  local d = mkTestTree()
  assertEq(ds.readPath'.out/civix/a.txt', 
  'for civix a test')
  assertEq(ds.readPath'.out/civix/b/b1.txt', '1 in dir b/')
  assertEq(ds.readPath'.out/civix/b/b2.txt', '2 in dir b/')
end)

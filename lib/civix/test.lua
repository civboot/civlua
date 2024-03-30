METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local test, assertEq; pkg.auto'civtest'

local posix = pkg.maybe'posix'
local civix  = pkg'civix'
local D = 'lib/civix/'

local function shouldSkip()
  if not posix then
    print" (skipping: install luaposix)"
    return true
  end
end

test('sh', function()
  local sh = civix.sh
  do
    local s = sh{'/usr/bin/false', 'a', 'b'}; assert(s)
    s:wait(); assertEq(1, s:rc())
  end
  -- do
  --   local s = sh{'true'}; assert(s)
  --   s:wait(); assertEq(0, s:rc())
  -- end

  -- result = sh([[ echo '<stderr from test>' 1>&2 ]],
  --             {err=true})
  -- assert('<stderr from test>', result.err)

  -- local cmd = {'echo', foo='bar'}
  -- assertEq("echo --foo='bar'", shCmd{'echo', foo='bar'})
  -- assertEq('--foo=bar\n'  ,  sh{'echo', foo='bar'}.out)
  -- assert(select(3, shCmd{foo="that's bad"})) -- assert error
  -- assertEq('from pipe', sh([[ cat ]], {inp='from pipe'}).out)
end)

local function testTime()
  if shouldSkip() then return end
  local period, e1 = ds.Duration(0.001), civix.epoch()
  for i=1,10 do
    civix.sleep(period)
    local e2 = civix.epoch()
    local result = e2 - e1; assert((e2 - e1) > period, result)
    e1 = e2
  end
end
test('time', function()
  testTime()

  local posix = civix.posix; civix.posix = nil
  testTime()
  civix.posix = posix
end)

test('mkTree', function()
  local d = '.out/civix/'
  if civix.exists(d) then civix.rmDir(d, true) end
  civix.mkTree(d, {
    ['a.txt'] = 'for civix a test',
    b = {
      ['b1.txt'] = '1 in dir b/',
      ['b2.txt'] = '2 in dir b/',
    },
  }, true)
  assertEq(ds.readPath'.out/civix/a.txt', 'for civix a test')
  assertEq(ds.readPath'.out/civix/b/b1.txt', '1 in dir b/')
  assertEq(ds.readPath'.out/civix/b/b2.txt', '2 in dir b/')
end)

test('walk', function()
  local f, d = civix.ls{D}
  local rspec = ds.indexOfPat(f, '%.rockspec')
  if rspec then table.remove(f, rspec) end
  ::clean::
  rspec = ds.indexOfPat(f, '%..?o') or ds.indexOfPat(f, '%.dylib')
  if rspec then table.remove(f, rspec); goto clean end
  table.sort(f); table.sort(d)
  local expected = {
      D..".gitignore",     D.."Makefile",
      D.."PKG.lua",        D.."README.md",
      D.."civix.lua",
      D..'civix/lib.c',    D..'civix/term.lua',
      D.."runterm.lua",
      D.."test.lua",       D.."test_term.lua",
  }
  assertEq(expected,         f)
  assertEq({D, D..'civix/'}, d)
end)


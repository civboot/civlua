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

test('fork', function()
  if shouldSkip() then return end
  local fork = civix.Fork(true, true)
  local p = fork.pipes
  assert(not p.lr and not p.lw)
  if not fork.isParent then
    local got, err =  p.r:read('a')
    assertEq(nil, err)
    io.stdout:write('I heard: '..got) -- send to test
    p:close()
    os.exit(42)
  end
  p.w:write('to my child');  p.w:close()
  local got, err = p.r:read('a');
  assertEq(nil, err)
  assertEq('I heard: to my child', got)
  assert(fork:wait())
end)

test('exec', function()
  if shouldSkip() then return end
  local fork = civix.Fork(true, false, true)
  local p = fork.pipes
  if not fork.isParent then
    assert(not p.r and not p.lr)
    print'Child executing'
    io.stderr:write'Child executing (stderr)\n'
    fork:exec([[
      SANTA='Santa Clause'; echo "Hi I am $SANTA, ho ho ho"
    ]]) -- EXITS child
  end
  assert(not p.w and p.lr and not p.lw)
  local got, err = p.r:read'a'
  assertEq(nil, err)
  assertEq('Child executing\nHi I am Santa Clause, ho ho ho\n', got)
  assertEq('Child executing (stderr)\n', p.lr:read'a')
  assert(fork:wait())
end)

test('sh', function()
  if shouldSkip() then return end
  local sh, shCmd; pkg.auto(civix)
  assertEq('on stdout\n', sh[[ echo 'on' stdout ]].out)
  assertEq(''           , sh[[ echo '<stderr from test>' 1>&2 ]].out)
  local result = sh('false', {check=false})
  assertEq(1, result.rc)

  result = sh([[ echo '<stderr from test>' 1>&2 ]],
              {err=true})
  assert('<stderr from test>', result.err)

  local cmd = {'echo', foo='bar'}
  assertEq("echo --foo='bar'", shCmd{'echo', foo='bar'})
  assertEq('--foo=bar\n'  ,  sh{'echo', foo='bar'}.out)
  assert(select(3, shCmd{foo="that's bad"})) -- assert error
  assertEq('from pipe', sh([[ cat ]], {inp='from pipe'}).out)
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


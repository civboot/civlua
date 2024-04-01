METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local test, assertEq; pkg.auto'civtest'

local posix = pkg.maybe'posix'
local civix  = pkg'civix'
local lib = pkg'civix.lib'
local C = lib.consts
local D = 'lib/civix/'

local function shouldSkip()
  if not posix then
    print" (skipping: install luaposix)"
    return true
  end
end

test('sh', function()
  do -- direct usage of civ.lib
    local sh, r, w, lr = lib.sh('true', {'true'})
    local ftype = r:ftype(); print('!! ftype', ftype)
    assert(ds.Set{'pipe', 'fifo'}[ftype], ftype)
    ftype = w:ftype()
    assert(ds.Set{'pipe', 'fifo'}[ftype], ftype)
    w:close()
    assertEq('', lib.read(r)); r:close(); lr:close()
    sh:wait(); assertEq(0, sh:rc())
  end

  local sh = civix.sh
  local rc, o, l = sh'false'; assertEq(1, rc)
    assertEq('', o)

  rc, o, l = sh'true'; assertEq(0, rc)
    assertEq('', o)

  rc, o, l = sh{'echo', 'hi there'}; assertEq(0, rc)
    assertEq('hi there\n', o)

  rc, o, l = sh('cat', 'from stdin'); assertEq(0, rc)
    assertEq('from stdin', o);

  rc, o, l = sh{'commandDoesNotExist', 'blah', 'blah'};
    assert(rc ~= 0);

  rc, o, l = sh{'echo', 'foo', '--abc=ya', aa='bar', bb=42}; assertEq(0, rc)
    assertEq('foo --abc=ya --aa=bar --bb=42\n', o)
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
  assertEq(ds.readPath'.out/civix/a.txt', 
  'for civix a test')
  assertEq(ds.readPath'.out/civix/b/b1.txt', '1 in dir b/')
  assertEq(ds.readPath'.out/civix/b/b2.txt', '2 in dir b/')
end)

test('fdth', function()
  do
    local d = '.out/civix/'; if civix.exists(d) then civix.rmDir(d, true) end
    civix.mkTree(d, { ['a.txt'] = 'for civix a test' }, true)

    local fdth = lib.fdth()
    fdth:_fill(d..'a.txt')
    fdth:_runop(C.FD_OPEN)
    while not fdth:isDone() do end

    fdth:_runop(C.FD_READ, 0, 128)
    while not fdth:isDone() do end
    assertEq('for civix a test', fdth:_buf())

    fdth:_runop(C.FD_CLOSE)
    while not fdth:isDone() do end
    fdth:destroy()
  end
  do local fdth = lib.fdth() end; collectgarbage()
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


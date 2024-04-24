METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local test, assertEq; pkg.auto'civtest'

local civix  = pkg'civix'
local lib = pkg'civix.lib'
local C = lib.consts
local D = 'lib/civix/'
local push = table.insert

test('sh', function()
  do -- direct usage of civ.lib
    local sh, r, w, lr = lib.sh('true', {'true'})
    local ftype = r:ftype(); print('!! ftype', ftype)
    assert(ds.Set{'pipe', 'fifo'}[ftype], ftype)
    ftype = w:ftype()
    assert(ds.Set{'pipe', 'fifo'}[ftype], ftype)
    w:close()
    assertEq('', r:_read()); r:close(); lr:close()
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

-- test('fdth', function()
--     local d = '.out/civix/';
--     if civix.exists(d) then civix.rmRecursive(d, true) end
-- 
--     civix.mkTree(d, { ['a.txt'] = 'for civix a test' }, true)
--     do
--       local fd = lib.fdopen(d..'a.txt', 0 | C.O_RDONLY)
--       assertEq('for civix a test', fd:_read(42))
--       assert(fd:fileno()); fd:close(); assertEq(nil, fd:fileno())
--     end
--     do
--       local fd = lib.fdopen(d..'b.txt', 0 | C.O_RDWR | C.O_CREAT | C.O_TRUNC)
--       local str = 'writing some bits'
--       local pos, err = fd:_write(str); assert(not err)
--       assertEq(#str + 1, pos)
--     end
-- end)
-- 
-- test('fdth', function()
--   do
--     local d = '.out/civix/'
--     if civix.exists(d) then civix.rmRecursive(d, true) end
--     civix.mkTree(d, { ['a.txt'] = 'for civix a test' }, true)
-- 
--     local fdth = lib.fdth()
--     fdth:_fill(d..'a.txt')
--     fdth:_runop(C.FD_OPEN)
--     while not fdth:isDone() do end
-- 
--     fdth:_runop(C.FD_READ, 0, 128)
--     while not fdth:isDone() do end
--     assertEq('for civix a test', fdth:_buf())
-- 
--     fdth:_runop(C.FD_CLOSE)
--     while not fdth:isDone() do end
--     fdth:destroy()
--   end
--   do local fdth = lib.fdth() end; collectgarbage()
-- end)
-- 
-- test('ls', function()
--   local D = mkTestTree()
--   local f, d = civix.ls{D}
--   table.sort(f); table.sort(d)
--   assertEq({ D..'a.txt' },   f)
--   assertEq({ D, D..'b/' }, d)
-- end)
-- 
-- test('lines', function()
--   local path, expect = '.out/lines.txt', {}
--   do
--     local f = io.open(path, 'w')
--     for i=1,100 do
--       local l = 'line '..i..' is a really great line'
--       push(expect, l); f:write(l, '\n')
--     end
--     f:flush(); f:close()
--   end
--   do
--     local f = io.open(path)
--     local result = {}
--     for l in civix.lines(f, 'l') do push(result, l) end
--     assertEq(result, expect)
--     f:close()
--   end
-- end)

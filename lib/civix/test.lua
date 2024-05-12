METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'
local test, assertEq; ds.auto'civtest'
local fd = require'fd'

local M  = require'civix'
local lib = require'civix.lib'
local D = 'lib/civix/'
local push = table.insert

test('sh', function()
  local sh = M.sh
  local rc, o = sh'false'; assertEq(1, rc)
    assertEq('', o)

  rc, o = sh'true'; assertEq(0, rc)
    assertEq('', o)

  rc, o = sh{'echo', 'hi there'}; assertEq(0, rc)
    assertEq('hi there\n', o)

  rc, o = sh{stdin='from stdin', 'cat'}; assertEq(0, rc)
    assertEq('from stdin', o);

  rc, o = sh{'commandDoesNotExist', 'blah', 'blah'};
    assert(rc ~= 0);

  rc, o = sh{'echo', 'foo', '--abc=ya', aa='bar', bb=42}; assertEq(0, rc)
    assertEq('foo --abc=ya --aa=bar --bb=42\n', o)
  collectgarbage()
end)

test('time', function()
  local period, e1 = ds.Duration(0.001), M.epoch()
  for i=1,10 do
    M.sleep(period)
    local e2 = M.epoch()
    local result = e2 - e1; assert((e2 - e1) > period, result)
    e1 = e2
  end
  M.sleep(-2.3)
  local m = M.mono(); M.sleep(0.001); assert(m < M.mono())
end)

local function mkTestTree()
  local d = '.out/civix/'
  if M.exists(d) then M.rmRecursive(d, true) end
  M.mkTree(d, {
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

test('fd-perf', function()
  local Kib = string.rep('123456789ABCDEF\n', 64)
  local data = string.rep(Kib, 500)
  local count, run = 0, true
  local res
  local O = '.out/'
  M.Lap{
    -- make sleep insta-ready instead (open/close use it)
    sleepFn = function(cor) LAP_READY[cor] = 'sleep' end,
  }:run{
    function() while run do
      count = count + 1; coroutine.yield(true)
    end end,
    function()
      local f = fd.openFDT(O..'perf.bin', 'w+')
      f:write(data); f:seek'set'; res = f:read()
      f:close()
      run = false
    end,
  }

  assert(data == res)
  assert(count > 50)
end)

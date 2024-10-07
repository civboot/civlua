METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'
local Iter = require'ds.Iter'
local T = require'civtest'
local assertEq, assertErrorPat; ds.auto'civtest'
local fd = require'fd'

local M  = require'civix'
local lib = require'civix.lib'
local D = 'lib/civix/'
local push = table.insert

T.lapTest('sh', function()
  local sh, o = M.sh

  assertEq('',           sh'true')
  assertEq('hi there\n', sh{'echo', 'hi there'})
  assertEq('from stdin', sh{stdin='from stdin', 'cat'})
  assertEq('foo --abc=ya --aa=bar --bb=42\n',
    sh{'echo', 'foo', '--abc=ya', aa='bar', bb=42})

  assertErrorPat('Command failed with rc=1', function() sh'false' end)
  assertErrorPat('Command failed with rc=', function()
    sh{'commandNotExist', 'blah'}
  end)
  -- error'FIXME: the above actually FAILED but test doesn't fail...'

  local path = '.out/echo.test'
  local f = io.open(path, 'w+')
  local out, err, s = sh{'echo', 'send to file', stdout=f}
  assertEq(nil, out); assertEq(nil, err);
  assertEq(nil, s.stdin); assertEq(nil, s.stdout)
  assertEq('send to file\n', io.open(path):read())
  f:seek'set'; assertEq('send to file\n', f:read())

  f:seek'set'
  out, err, s = sh{stdin=f, 'cat', stdout=io.open('.out/cat.test', 'w+')}
  assertEq(nil, out); assertEq(nil, err)
  assertEq('send to file\n', io.open('.out/cat.test'):read())

  out, err, s = sh{'sh', '-c', "echo 'on STDERR' >&2 ", stdout=false, stderr=true}
  assertEq(nil, out); assertEq('on STDERR\n', err)
  collectgarbage()
end)

T.lapTest('time', function()
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

T.lapTest('mkTree', function()
  local d = mkTestTree()
  assertEq(ds.readPath'.out/civix/a.txt', 
  'for civix a test')
  assertEq(ds.readPath'.out/civix/b/b1.txt', '1 in dir b/')
  assertEq(ds.readPath'.out/civix/b/b2.txt', '2 in dir b/')
end)

T.test('fd-perf', function()
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
  -- assert(count > 50, tostring(count))
end)

T.test('walk', function()
  local d = mkTestTree()
  local paths, types, depths = {}, {}, {}
  local w = M.Walk{d}; for path, ty in w do
    push(paths, path); push(types, ty); push(depths, w:depth())
  end
  assertEq({
      ".out/civix/", ".out/civix/a.txt",
      ".out/civix/b/",
        ".out/civix/b/b1.txt",
        ".out/civix/b/b2.txt" }, paths)
  assertEq({'dir', 'file', 'dir', 'file', 'file'}, types)
  assertEq({1,     1,      2,     2,       2},     depths)
  assertEq(nil, w()); assertEq(nil, w());

  local w = M.Walk{d}
  local saw = {}; local function see(path) push(saw, path) end
  local skipB = function(path, ptype)
    return not path:find'/b/' or w:skip()
  end
  local expect = {".out/civix/", ".out/civix/a.txt", ".out/civix/b/"}
  assertEq(expect, Iter{w}:listen(skipB):keysTo())

  w = M.Walk{d}
  assertEq(
    {".out/civix/", ".out/civix/a.txt"},
    Iter{w}:listen(see):filterK(skipB):keysTo())
  assertEq(expect, saw)

end)

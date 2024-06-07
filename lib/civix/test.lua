METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'
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
  assert(count > 50)
end)

-------------------------
-- civix.term
local term = require'civix.term'

local function testU8(expect, chrs)
  local c = table.remove(chrs, 1)
  local lenMsk = term.U8MSK[0xF8 & c]; assert(lenMsk, 'lenMsk is nil')
  T.assertEq(#chrs, lenMsk[1] - 1)
  c = term.u8decode(lenMsk, c, chrs)
  T.assertEq(expect, utf8.char(c))
end

-- chrs were gotten from python:
--   print('{'+', '.join('0x%X' % c for c in '🙃'.encode('utf-8'))+'}')
-- Edge case characters are from:
--   https://design215.com/toolbox/ascii-utf8.php
T.test('u8edges', function()
  testU8('\0', {0})
  testU8(' ', {0x20})
  testU8('a', {string.byte('a')})
  testU8('~', {0x7E})

  testU8('¡', {0xC2, 0xA1})
  testU8('ƒ', {0xC6, 0x92})
  testU8('߿', {0xDF, 0xBF})

  testU8('ࠀ', {0xE0, 0xA0, 0x80})
  testU8('ἰ', {0xE1, 0xBC, 0xB0})
  testU8('‡', {0xE2, 0x80, 0xA1})
  testU8('➤', {0xE2, 0x9E, 0xA4})
  testU8('⮝', {0xE2, 0xAE, 0x9D})
  testU8('€', {0xE2, 0x82, 0xAC})
  testU8('�', {0xEF, 0xBF, 0xBD})

  testU8('𒀀',  {0xF0, 0x92, 0x80, 0x80})
  testU8('🙃', {0xF0, 0x9F, 0x99, 0x83})
  testU8('🧿', {0xF0, 0x9F, 0xA7, 0xBF})
end)

T.test('literal', function()
  local l = term.literal
  assertEq('a',  l'a')
  assertEq('\n', l'return')
  assertEq(nil,  l'invalid')
end)

T.test('keyError', function()
  local ke = term.keyError
  assertEq(nil, ke'a')
  assertEq(nil, ke'esc')
  assertEq(nil, ke'^A')
  assertEq(nil, ke'😜')
  assertEq('invalid key: "escape"', ke'escape')
  assertEq([[key "\8" not a printable character]], ke'\x08')
end)

T.test('keynice', function()
  local key, b = term.key, string.byte
  assertEq('a',      key(b'a'))
  assertEq('^a',     key(1))
  assertEq('tab',    key(9))
  assertEq('^j',     key(10))
  assertEq('return', key(13))
  assertEq('space',  key(32))
  assertEq('^z',     key(26))
end)

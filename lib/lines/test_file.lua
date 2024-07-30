local mty = require'metaty'
local ds = require'ds'
local test, assertEq, assertMatch, assertErrorPat; ds.auto'civtest'
local lines = require'lines'
local testing = require'lines.testing'
local U3File = require'lines.U3File'
local File = require'lines.File'

local push = table.insert

local loadu3s = function(f)
  local pos, t = f:seek'cur', {}
  assert(pos)
  f:seek'set'
  for u3 in f:lines(3) do push(t, (('>I3'):unpack(u3))) end
  f:seek('set', pos) -- reset
  return t
end

test('U3File', function()
  local u = U3File:create()
  u[1] = 11; u[2] = 22; u[3] = 33
  assertEq(11, u[1])
  assertEq(22, u[2])
  assertEq(33, u[3]); assertEq(nil, rawget(u, 3))
  assertEq({11, 22, 33}, loadu3s(u.f))
  assertEq(11, u[1]) -- testing loadu3s
  assertEq(3, #u)

  u[2] = 20; assertEq({11, 20, 33}, loadu3s(u.f))
  assertEq(20, u[2])
  assertEq(33, u[3])

  u[1] = 10; u[4] = 44; u[5] = 55
  assertEq({10, 20, 33, 44, 55}, loadu3s(u.f))
  assertEq(10, u[1])
  assertEq(55, u[5])

  local l = {}; for i, v in ipairs(u) do l[i] = v end
  assertEq({10, 20, 33, 44, 55}, l)
  assertEq(5, #u)
end)

test('reindex', function()
  local reindex = getmetatable(File).reindex
  local idx, f = {}, io.tmpfile()
  local txt = 'hi\nthere\nindex'
  f:write(txt); f:flush(); f:seek'set'
  assertEq(#txt, reindex(f, idx))
    assertEq({0, 3, 9}, idx)

  idx = {} f:write'\n'; f:flush(); f:seek'set'
  assertEq(#txt + 1, reindex(f, idx))
    assertEq({0, 3, 9, 15}, idx)

  -- test indexing from a l,pos
  idx = {0, 3}; f:seek('set', 9)
  assertEq(#txt + 1, reindex(f, idx, 3, 9))
    assertEq({0, 3, 9, 15}, idx)
end)

test('File', function()
  local f = assert(File:create()); f.cache = ds.Forget{}
  assertEq('lines.File()', mty.tostring(f))
  assertEq(0, #f); assertEq({}, f:tolist());

  local dat = {'one', 'two', 'three'}
  ds.extend(f, dat)
    assertEq({0, 4, 8}, f.idx:tolist())
    assertEq('one',   f[1])
    assertEq('three', f[3])
    assertEq(dat, f:tolist())

  assertEq('one', f[1])
  push(f, 'four'); push(dat, 'four')
    assertEq(dat, f:tolist())
  assertEq(4, #f); assertEq('four', f[#f])

  f:write': still in line four'; f:flush()
  assertEq('four: still in line four',          f[4])
  f:write' and this'
  assertEq('four: still in line four and this', f[4])

  local small = ds.srcdir()..'testdata/small.txt'
  assertEq('one\ntwo\nthree\n', ds.readPath(small))
  f = assert(File:load(small)); f.cache = ds.Forget{}
  assertEq({'one', 'two', 'three', ''}, f:tolist())
  assertEq('two', f[2])
end)

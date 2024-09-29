local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local test, assertEq, assertMatch, assertErrorPat; ds.auto'civtest'
local lines = require'lines'
local testing = require'lines.testing'
local U3File  = require'lines.U3File'
local File    = require'lines.File'
local EdFile  = require'lines.EdFile'
local Gap     = require'lines.Gap'

local push, icopy = table.insert, ds.icopy

local TXT, IDX = '.out/lines.txt', '.out/lines.idx'
local SMALL = ds.srcdir()..'testdata/small.txt'

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

  u = U3File:create(IDX)
  ds.extend(u, {0, 3, 5, 7})
  assertEq(0, u[1])
  assertEq(7, u[4])
end)

test('reindex', function()
  local reindex = File._reindex
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
  local f = assert(File()); f.cache = ds.Forget{}
  assertEq('lines.File()', fmt(f))
  assertEq(0, #f); assertEq({}, ds.icopy(f))

  local dat = {'one', 'two', 'three'}
  ds.extend(f, dat)
    assertEq({0, 4, 8}, ds.icopy(f.idx))
    assertEq('one',   f[1])
    assertEq('three', f[3])
    assertEq(dat, ds.icopy(f))

  assertEq('one', f[1])
  push(f, 'four'); push(dat, 'four')
    assertEq(dat, ds.icopy(f))
  assertEq(4, #f); assertEq('four', f[#f])

  f:write': still in line four'; f:flush()
  assertEq('four: still in line four',          f[4])
  f:write' and this'
  assertEq('four: still in line four and this', f[4])

  assertEq('one\ntwo\nthree\n', ds.readPath(SMALL))
  f = assert(File(SMALL)); f.cache = ds.Forget{}
  assertEq({'one', 'two', 'three', ''}, ds.icopy(f))
  assertEq('two', f[2])

  f = File(TXT, 'w+')
  f:write'line 1\nline 2\nline 3'
  assertEq({0, 7, 14}, ds.icopy(f.idx))
  assertEq({'line 1', 'line 2', 'line 3'}, ds.icopy(f))
  f:flush()

  local r = f:reader()
  assertEq({'line 1', 'line 2', 'line 3'}, ds.icopy(r))
end)

local function edEq(a, b)
  assertEq(EdFile, getmetatable(a))
  assertEq(EdFile, getmetatable(b))
  assertEq(ds.icopy(a), ds.icopy(b))
end

test('EdFile.index', function()
  local ef = mty.construct(EdFile, {lens={}, dats={
    ds.Slc{si=1, ei=2},
    ds.Slc{si=3, ei=6},
  }})

  -- test indexing logic itself
  assertEq(1, ef:_datindex(1))
  assertEq(1, ef:_datindex(2))
  assertEq({2}, ef.lens)

  assertEq(2, ef:_datindex(3))
  assertEq({2, 6}, ef.lens)
  assertEq(2, ef:_datindex(6))
  assertEq(6, #ef)

  ef.lens[2] = nil
  assertEq(nil, ef:_datindex(7))
  assertEq({2, 6}, ef.lens)
  assertEq(nil, ef:_datindex(0))

  -- test getting the index
  ef.dats = {
    {'one', 'two'},
    {'three', 'four', 'five', 'six'},
  }
  ef.lens = {}
  assertEq('one',   ef[1]); assertEq({2},    ef.lens)
  assertEq('three', ef[3]); assertEq({2, 6}, ef.lens)
  assertEq('six',   ef[6])
  assertEq(6, #ef)
end)

test('EdFile.newindex', function()
  local S = function(si, ei) return ds.Slc{si=si, ei=ei} end
  local ef = EdFile()
  assertEq(0, #ef)
  assertEq({S(1, 0)},    ef.dats)

  push(ef, 'one')
  assertEq({S(1,1)}, ef.dats)
  assertEq({1},      ef.lens)
  assertEq('one', ef[1])

  push(ef, 'two')
  assertEq({S(1,2)}, ef.dats)
  assertEq({2}, ef.lens)
  assertEq('one', ef[1])
  assertEq('two', ef[2])

  ef[1] = 'one 1'
  assertEq({Gap'one 1', S(2,2)}, ef.dats)
  assertEq({}, ef.lens)
  assertEq({'one 1', 'two'}, icopy(ef))
  assertEq({1, 2}, ef.lens); assertEq(2, #ef)
end)

test('EdIter', function()
  local ed = EdFile(SMALL)
  local small = {'one', 'two', 'three', ''}
  assertEq(small, ds.icopy(ed))

  local ln, t = {}, {};
  for i, line in ed:iter() do push(ln, i); push(t, line) end
  assertEq({1, 2, 3, 4}, ln)
  assertEq(small, t)
end)

test('EdFile.write', function()
  local ed = EdFile(TXT, 'w+')
  ed:write'one\nthree\nfive'
  ed:flush()
  assertEq(3, #ed)
  assertEq('one\nthree\nfive', ds.readPath(TXT))
  assertEq({ds.Slc{si=1, ei=3}}, ed.dats)
  ed:write' 5'
  assertEq('five 5', ed[3])

  ds.inset(ed, 2, {'two'})
  local expect = {'one', 'two', 'three', 'five 5'}
  assertEq(expect, ds.icopy(ed))
  ds.inset(ed, 1, {'zero'})
  assertEq({
    'zero', 'one', 'two', 'three', 'five 5'
  }, ds.icopy(ed))
  assertEq({
    Gap'zero',
    ds.Slc{si=1, ei=1}, -- one
    Gap'two',
    ds.Slc{si=2, ei=3}, -- three\nfive 5
  }, ed.dats)

  ds.inset(ed, 1, {'zero 0', 'one 1'}, 2)
  expect = {
    'zero 0', 'one 1',
    'two', 'three', 'five 5'
  }
  assertEq(expect, ds.icopy(ed))
  assertEq({
    Gap'zero 0\none 1\ntwo',
    ds.Slc{si=2, ei=3}, -- three\nfive 5
  }, ed.dats)
  assertEq(5, #ed)
  ed[1] = 'zero 0' -- same
  assertEq(expect, ds.icopy(ed))
end)

test('EdFile.big', function()
  local ed = EdFile(TXT, 'w+')
  for i=1,100 do push(ed, 'line '..i) end
  assertEq(100, #ed)

  assertEq(ed[3], 'line 3')
  assertEq({ds.Slc{si=1, ei=100}}, ed.dats)

  ed[3] = 'line 3.0'
  assertEq(ed[2], 'line 2')
  assertEq(ed[3], 'line 3.0')
  assertEq(ed[4], 'line 4')

  ds.inset(ed, 7, {'line 7.0', 'line 7.1', 'line 7.2'}, 1)
  assertEq(ed[6], 'line 6')
  assertEq(ed[7], 'line 7.0')
  assertEq(ed[10], 'line 8')
  assertEq(102, #ed)
end)

local function newEdFile(text, ...)
  print('!! newEdFile', ...)
  local ed = EdFile()
  if type(text) == 'string' then ed:write(text)
  else ds.extend(ed, text) end
  ed:flush()
  return ed
end

test('EdFile.linesOffset', function()
  testing.testOffset(newEdFile(testing.DATA.offset))
end)

test('EdFile.linesRemove', function()
  testing.testLinesRemove(newEdFile, edEq, ds.noop)
end)

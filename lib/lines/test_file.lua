local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local pth = require'ds.path'

local T = require'civtest'.Test()
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

T.U3File = function()
  local u = U3File:create()
  u[1] = 11
  u[2] = 22; u[3] = 33
  T.eq(11, u[1])
  T.eq(22, u[2])
  T.eq(33, u[3]); T.eq(nil, rawget(u, 3))
  T.eq({11, 22, 33}, loadu3s(u.f))
  T.eq(11, u[1]) -- testing loadu3s
  T.eq(3, #u)

  u[2] = 20; T.eq({11, 20, 33}, loadu3s(u.f))
  T.eq(20, u[2])
  T.eq(33, u[3])

  u[1] = 10; u[4] = 44; u[5] = 55
  T.eq({10, 20, 33, 44, 55}, loadu3s(u.f))
  T.eq(10, u[1])
  T.eq(55, u[5])

  local l = {}; for i, v in ipairs(u) do l[i] = v end
  T.eq({10, 20, 33, 44, 55}, l)
  T.eq(5, #u)

  u = U3File:create(IDX)
  ds.extend(u, {0, 3, 5, 7})
  T.eq(0, u[1])
  T.eq(7, u[4])
end

T.reindex = function()
  local reindex = File._reindex
  local idx, f = {}, io.tmpfile()
  local txt = 'hi\nthere\nindex'
  f:write(txt); f:flush(); f:seek'set'
  T.eq(#txt, reindex(f, idx))
    T.eq({0, 3, 9}, idx)

  idx = {} f:write'\n'; f:flush(); f:seek'set'
  T.eq(#txt + 1, reindex(f, idx))
    T.eq({0, 3, 9, 15}, idx)

  -- test indexing from a l,pos
  idx = {0, 3}; f:seek('set', 9)
  T.eq(#txt + 1, reindex(f, idx, 3, 9))
    T.eq({0, 3, 9, 15}, idx)
end

T.File = function()
  local f = assert(File()); f.cache = ds.Forget{}
  T.eq('lines.File()', fmt(f))
  T.eq(0, #f); T.eq({}, ds.icopy(f))

  local dat = {'one', 'two', 'three'}
  ds.extend(f, dat)
    T.eq({0, 4, 8}, ds.icopy(f.idx))
    T.eq('one',   f[1])
    T.eq('three', f[3])
    T.eq(dat, ds.icopy(f))

  T.eq('one', f[1])
  push(f, 'four'); push(dat, 'four')
    T.eq(dat, ds.icopy(f))
  T.eq(4, #f); T.eq('four', f[#f])

  f:write': still in line four'; f:flush()
  T.eq('four: still in line four',          f[4])
  f:write' and this'
  T.eq('four: still in line four and this', f[4])

  T.eq('one\ntwo\nthree\n', pth.read(SMALL))
  f = assert(File{path=SMALL}); f.cache = ds.Forget{}
  T.eq({'one', 'two', 'three', ''}, ds.icopy(f))
  T.eq('two', f[2])

  f = File{path=TXT, mode='w+'}
  f:write'line 1\nline 2\nline 3'
  T.eq({0, 7, 14}, ds.icopy(f.idx))
  T.eq({'line 1', 'line 2', 'line 3'}, ds.icopy(f))
  f:flush()

  local r = f:reader()
  T.eq({'line 1', 'line 2', 'line 3'}, ds.icopy(r))
end

local function edEq(a, b)
  T.eq(EdFile, getmetatable(a))
  T.eq(EdFile, getmetatable(b))
  T.eq(ds.icopy(a), ds.icopy(b))
end

T.EdFile_index = function()
  local ef = mty.construct(EdFile, {lens={}, dats={
    ds.Slc{si=1, ei=2},
    ds.Slc{si=3, ei=6},
  }})

  -- test indexing logic itself
  T.eq(1, ef:_datindex(1))
  T.eq(1, ef:_datindex(2))
  T.eq({2}, ef.lens)

  T.eq(2, ef:_datindex(3))
  T.eq({2, 6}, ef.lens)
  T.eq(2, ef:_datindex(6))
  T.eq(6, #ef)

  ef.lens[2] = nil
  T.eq(nil, ef:_datindex(7))
  T.eq({2, 6}, ef.lens)
  T.eq(nil, ef:_datindex(0))

  -- test getting the index
  ef.dats = {
    {'one', 'two'},
    {'three', 'four', 'five', 'six'},
  }
  ef.lens = {}
  T.eq('one',   ef[1]); T.eq({2},    ef.lens)
  T.eq('three', ef[3]); T.eq({2, 6}, ef.lens)
  T.eq('six',   ef[6])
  T.eq(6, #ef)
end

T.EdFile_newindex = function()
  local S = function(si, ei) return ds.Slc{si=si, ei=ei} end
  local ef = EdFile()
  T.eq(0, #ef)
  T.eq({S(1, 0)},    ef.dats)

  push(ef, 'one')
  T.eq({S(1,1)}, ef.dats)
  T.eq({1},      ef.lens)
  T.eq('one', ef[1])

  push(ef, 'two')
  T.eq({S(1,2)}, ef.dats)
  T.eq({2}, ef.lens)
  T.eq('one', ef[1])
  T.eq('two', ef[2])

  ef[1] = 'one 1'
  T.eq({Gap'one 1', S(2,2)}, ef.dats)
  T.eq({}, ef.lens)
  T.eq({'one 1', 'two'}, icopy(ef))
  T.eq({1, 2}, ef.lens); T.eq(2, #ef)
end

T.EdIter = function()
  local ed = EdFile(SMALL)
  local small = {'one', 'two', 'three', ''}
  T.eq(small, ds.icopy(ed))

  local ln, t = {}, {};
  for i, line in ed:iter() do push(ln, i); push(t, line) end
  T.eq({1, 2, 3, 4}, ln)
  T.eq(small, t)
end

T.EdFile_write = function()
  local ed = EdFile(TXT, 'w+')
  ed:write'one\nthree\nfive'
  ed:flush()
  T.eq(3, #ed)
  T.eq('one\nthree\nfive', pth.read(TXT))
  T.eq({ds.Slc{si=1, ei=3}}, ed.dats)
  ed:write' 5'
  T.eq('five 5', ed[3])

  ds.inset(ed, 2, {'two'})
  local expect = {'one', 'two', 'three', 'five 5'}
  T.eq(expect, ds.icopy(ed))
  ds.inset(ed, 1, {'zero'})
  T.eq({
    'zero', 'one', 'two', 'three', 'five 5'
  }, ds.icopy(ed))
  T.eq({
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
  T.eq(expect, ds.icopy(ed))
  T.eq({
    Gap'zero 0\none 1\ntwo',
    ds.Slc{si=2, ei=3}, -- three\nfive 5
  }, ed.dats)
  T.eq(5, #ed)
  ed[1] = 'zero 0' -- same
  T.eq(expect, ds.icopy(ed))
end

T.EdFile_big = function()
  local ed = EdFile(TXT, 'w+')
  for i=1,100 do push(ed, 'line '..i) end
  T.eq(100, #ed)

  T.eq(ed[3], 'line 3')
  T.eq({ds.Slc{si=1, ei=100}}, ed.dats)

  ed[3] = 'line 3.0'
  T.eq(ed[2], 'line 2')
  T.eq(ed[3], 'line 3.0')
  T.eq(ed[4], 'line 4')

  ds.inset(ed, 7, {'line 7.0', 'line 7.1', 'line 7.2'}, 1)
  T.eq(ed[6], 'line 6')
  T.eq(ed[7], 'line 7.0')
  T.eq(ed[10], 'line 8')
  T.eq(102, #ed)
end

local function newEdFile(text, ...)
  local ed = EdFile()
  if type(text) == 'string' then ed:write(text)
  else ds.extend(ed, text) end
  ed:flush()
  return ed
end

T.EdFile_linesOffset = function()
  testing.testOffset(newEdFile(testing.DATA.offset))
end

T.EdFile_linesRemove = function()
  testing.testLinesRemove(newEdFile, edEq, ds.noop)
end

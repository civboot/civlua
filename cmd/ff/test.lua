-- test for ff
-- Many of these involve writing some text files and dirs to .out/ff/
-- and then using it to

local pkg = require'pkglib'
local shim = require'shim'
local mty = require'metaty'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local civix  = require'civix'
local T = require'civtest'
local ff = require'ff'

local push, sfmt = table.insert, string.format

local dir = '.out/ff/'
if civix.exists(dir) then civix.rmRecursive(dir) end
local a = {}; for i=1,100 do push(a, 'a '..i) end
local b = {}; for i=1,100 do push(b, 'b '..i) end

local NOPATH = {"^%..*/", "/%..*/"}
civix.mkTree(dir, {
  ['a.txt'] = table.concat(a, '\n'),
  b = {
    ['b1.txt'] = table.concat(b, '\n'),
    ['b2.txt'] = 'mostly empty',
  },
}, true)

local function seekRead(f)
  f:seek'set'; local s = f:read'*a'
  f:seek'set'; return s
end

local function expectSimple(fmt)
  local t = {}
  for i=1,9 do push(t, sfmt(fmt, i, i)) end
  return table.concat(t, '\n')..'\n'
end

local function simpleSub(fmt, subfmt)
  local t = {}
  for i=1,9 do
    push(t, sfmt(fmt, i, i))
    push(t, sfmt(subfmt, i))
  end
  return table.concat(t, '\n')..'\n'
end

T.ff_Main = function()
  local m = ff.Main{'a', 'p:b/c', '-b', '-p:%.ef', 'r:r1/', '--', 'r2/'}
  T.eq(mty.construct(ff.Main, {
    root={'r2/', 'r1/'},
    pat={'a'},    nopat={'b'},
    path={'b/c'}, nopath={'%.ef'},
  }), m)

  local m = ff.Main(shim.parse{'a', '--sub=b', 'p:dir/',
                                '--', 'root/', '--weird'})
  T.eq(mty.construct(ff.Main, {
    root={'root/', '--weird'},
    pat={'a'},    nopat={},
    path={'dir/'}, nopath=NOPATH,
    sub = 'b',
  }), m)
end

local function runFF(args) --> ok, paths, stdout, stderr
  local ll = LOGLEVEL; LOGLEVEL = 0
  local f, out = fmt.Fmt{to=io.tmpfile()}, io.tmpfile()
  local iofmt, ioout = io.fmt, io.stdout
  io.fmt, io.stdout = f, out
  local ok, paths = ds.try(ff, args)
  io.fmt, io.stdout = iofmt, ioout
  f.to:seek'set'; out:seek'set'
  LOGLEVEL = ll
  return ok, paths, out:read'a', f.to:read'a'
end

local function testA()
  local ok, res, stdout, stderr = runFF{'-p:', 'a %d1', '--', dir}
  assert(ok, res)
  T.eq({dir..'a.txt'}, res)
  T.eq(dir..'a.txt\n', stdout)
  T.eq(expectSimple'    %i1 a %i1', stderr)

  -- do without -p: means .out/ never gets searched
  -- (because of default)
  local ok, res, stdout, stderr = runFF{'a %d1', '--', dir}
  assert(ok, res)
  T.eq({}, res); T.eq('', stdout); T.eq('', stderr)
end

T.ff_find = function()
  testA()

  local bArgs = {'-p:', 'b %d1', '--', dir}
  local ok, res, stdout, stderr = runFF(ds.copy(bArgs))
  assert(ok, res)
  T.eq({dir..'b/b1.txt'}, res)
  T.eq(dir..'b/b1.txt\n', stdout)
  T.eq(expectSimple'    %i1 b %i1', stderr)

  -- adding /b/ does nothing
  local ok, res, stdout, stderr = runFF{'-p:', 'b %d1', 'p:/b/', 'r:'..dir}
  assert(ok, res);
  T.eq({dir..'b/b1.txt'}, res)
end

T.ff_sub = function()
  local subArgs = {'-p:', 'a (%d1)', sub='s %1', '--', dir}
  local ok, res, stdout, stderr = runFF(ds.copy(subArgs))
  assert(ok, res)
  T.eq({dir..'a.txt'}, res)
  T.eq(simpleSub('    %i1 a %i1', '   --> s %i1'), stderr)

  testA() -- not mutated

  -- mutate it with sub
  local ok, res, stdout, stderr = runFF(ds.copy(subArgs, {mut=true}))
  assert(ok, res)
  T.eq({dir..'a.txt'}, res)
  T.eq(simpleSub('    %i1 a %i1', '   --> s %i1'), stderr)

  -- there are no more 'a %i1'
  local ok, res, stdout, stderr = runFF(ds.copy(subArgs))
  assert(ok, res)
  T.eq({}, res); T.eq('', stderr) -- no matches

  -- there are 's %i1'
  local ok, res, stdout, stderr = runFF{'-p:', 's %d1', 'r:'..dir}
  assert(ok, res)
  T.eq({dir..'a.txt'}, res)
  T.eq(expectSimple'    %i1 s %i1', stderr)
end

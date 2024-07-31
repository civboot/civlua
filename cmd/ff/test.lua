-- test for ff
-- Many of these involve writing some text files and dirs to .out/ff/
-- and then using it to

local pkg = require'pkglib'
local mty = require'metaty'
local ds, lines = require'ds', require'lines'
local civix  = require'civix'
local test, assertEq; ds.auto'civtest'
local ff = require'ff'

local add, sfmt = table.insert, string.format

local dir = '.out/ff/'
if civix.exists(dir) then civix.rmRecursive(dir) end
local a = {}; for i=1,100 do add(a, 'a '..i) end
local b = {}; for i=1,100 do add(b, 'b '..i) end

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

local function expectSimple(path, fmt)
  local expect = {path}
  for i=1,9 do add(expect, sfmt(fmt, i, i)) end
  return table.concat(expect, '\n')..'\n'
end

test('ff pat', function()
  local f = io.open('.out/TEST', 'w+')
  ff{dir, pat='a %d1', log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1 a %i1'),
    seekRead(f))
  ff{dir, '%a %d1', log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1 a %i1'),
    seekRead(f))
end)

test('ff recursive', function()
  local f = io.open('.out/TEST', 'w+')
  ff{dir, pat='b %d1', depth=1, log=f}
  assertEq('', seekRead(f))
  ff{dir, pat='b %d1', depth=1, log=f}
  assertEq('', seekRead(f))
  ff{dir, pat='b %d1', log=f} -- default depth=-1
  assertEq(
    expectSimple('.out/ff/b/b1.txt', '    %i1 b %i1'),
    seekRead(f))
end)

test('ff sub', function()
  local f = io.open('.out/TEST', 'w+')
  ff{dir..'a.txt', pat='(a %d)1', sub='%1A', log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1 a %iA'),
    seekRead(f))

  f:close(); f = io.open('.out/TEST', 'w+')
  ff{dir..'a.txt', m=true, pat='(a %d)1', sub='%1A',
    log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1 a %iA'),
    seekRead(f))

  -- now we won't find them (they were substituted)
  f:close(); f = io.open('.out/TEST', 'w+')
  ff{dir..'a.txt', pat='a %d1', log=f}
  assertEq('', seekRead(f))

  -- change it back
  ff{dir..'a.txt', m=true, pat='(a %d)A', sub='%11',
    log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1 a %i1'),
    seekRead(f))
end)

test('ff mv', function()
  local f = io.open('.out/TEST', 'w+')
  ff{dir, incl='b%d.txt', log=f}
  local result = lines(seekRead(f)); table.sort(result)
  local expected = {'', ".out/ff/b/b1.txt", ".out/ff/b/b2.txt"}
  assertEq(expected, result)

  ff{dir, incl='b(%d.txt)', mv='bb%1', log=f}
  local result = lines(seekRead(f)); table.sort(result)
  local expected = {
    "",
    " -> .out/ff/b/bb1.txt",
    " -> .out/ff/b/bb2.txt",
    "mv  .out/ff/b/b1.txt",
    "mv  .out/ff/b/b2.txt",
  }

  assertEq(expected, result)
  assertEq('mostly empty', ds.readPath(".out/ff/b/b2.txt"))

  ff{dir, m=true, incl='b(%d.txt)', mv='bb%1',
             log=f}
  local result = lines(seekRead(f)); table.sort(result)
  local expected = {
    '',
    " -> .out/ff/b/bb1.txt",
    " -> .out/ff/b/bb2.txt",
    "mv  .out/ff/b/b1.txt",
    "mv  .out/ff/b/b2.txt",
  }
  assertEq(expected, result)
  assert(not civix.exists".out/ff/b/b1.txt")
  assert(not civix.exists".out/ff/b/b2.txt")
  assertEq('mostly empty', ds.readPath(".out/ff/b/bb2.txt"))
  assertEq(table.concat(b, '\n'), ds.readPath(".out/ff/b/bb1.txt"))
end)

test('ff mv pat', function()
  local f = io.open('.out/TEST', 'w+')
  ff{dir, '%b (10)$', m=true,
     incl='(.*/)(.*%d.txt)', mv='%1/b%2',
     log=f}
  assertEq(
    'mv  .out/ff/b/bb1.txt\n'
  ..' -> .out/ff/b/bbb1.txt\n'
  ..'    10 b 10\n', seekRead(f))
  assertEq(expected, result)
  assert(not civix.exists".out/ff/b/bb1.txt")
  assert(civix.exists".out/ff/b/bbb1.txt")

  -- assertEq(table.concat(b, '\n'), ds.readPath(".out/ff/b/bb1.txt"))
end)

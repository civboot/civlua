-- test for ff
-- Many of these involve writing some text files and dirs to .out/ff/
-- and then using it to

local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local civix  = pkg'civix'
local test, assertEq; pkg.auto'civtest'
local ff = pkg'ff'

local add, sfmt = table.insert, string.format

local dir = '.out/ff/'
if civix.exists(dir) then civix.rmDir(dir, true) end
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
  ff.findfix{dir, pat='a %d1', log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1: a %i1'),
    seekRead(f))
  ff.findfix{dir, '%a %d1', r=true, log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1: a %i1'),
    seekRead(f))
end)

test('ff recursive', function()
  local f = io.open('.out/TEST', 'w+')
  ff.findfix{dir, pat='b %d1', depth=1, log=f}
  assertEq('', seekRead(f))
  ff.findfix{dir, pat='b %d1', log=f} -- default depth=1
  assertEq('', seekRead(f))
  ff.findfix{dir, r=true, pat='b %d1', log=f}
  assertEq(
    expectSimple('.out/ff/b/b1.txt', '    %i1: b %i1'),
    seekRead(f))
end)

test('ff sub', function()
  local f = io.open('.out/TEST', 'w+')
  ff.findfix{dir..'a.txt', r=true, pat='(a %d)1', sub='%1A', log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1: a %iA'),
    seekRead(f))

  f:close(); f = io.open('.out/TEST', 'w+')
  ff.findfix{dir..'a.txt', m=true, r=true, pat='(a %d)1', sub='%1A',
    log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1: a %iA'),
    seekRead(f))

  -- now we won't find them (they were substituted)
  f:close(); f = io.open('.out/TEST', 'w+')
  ff.findfix{dir..'a.txt', r=true, pat='a %d1', log=f}
  assertEq('', seekRead(f))

  -- change it back
  ff.findfix{dir..'a.txt', m=true, r=true, pat='(a %d)A', sub='%11',
    log=f}
  assertEq(
    expectSimple('.out/ff/a.txt', '    %i1: a %i1'),
    seekRead(f))
end)

test('ff fsub', function()
  local f = io.open('.out/TEST', 'w+')
  ff.findfix{dir, r=true, fpat='b%d.txt', log=f}
  local result = ds.lines(seekRead(f)); table.sort(result)
  local expected = {'', ".out/ff/b/b1.txt", ".out/ff/b/b2.txt"}
  assertEq(expected, result)

  ff.findfix{dir, r=true, fpat='b(%d.txt)', fsub='bb%1', log=f}
  local result = ds.lines(seekRead(f)); table.sort(result)
  local expected = {'', ".out/ff/b/bb1.txt", ".out/ff/b/bb2.txt"}
  assertEq(expected, result)
  assertEq('mostly empty', ds.readPath(".out/ff/b/b2.txt"))

  ff.findfix{dir, m=true, r=true, fpat='b(%d.txt)', fsub='bb%1',
             log=f}
  local result = ds.lines(seekRead(f)); table.sort(result)
  local expected = {'', ".out/ff/b/bb1.txt", ".out/ff/b/bb2.txt"}
  assertEq(expected, result)
  assert(not civix.exists".out/ff/b/b1.txt")
  assert(not civix.exists".out/ff/b/b2.txt")
  assertEq('mostly empty', ds.readPath(".out/ff/b/bb2.txt"))
  assertEq(table.concat(b, '\n'), ds.readPath(".out/ff/b/bb1.txt"))
end)

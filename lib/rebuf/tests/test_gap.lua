METATY_CHECK = true

local mty = require'metaty'
local ds, lines  = require'ds', require'ds.lines'
local dstest = require'ds.testing'
local test, assertEq; ds.auto'civtest'
local gap = require'rebuf.gap'
local Gap = gap.Gap
local tostring = mty.tostring

test('set', function()
  local g = Gap.new('ab\nc\n\nd')
  assertEq('ab\nc\n\nd', tostring(g))
  assertEq({'ab', 'c', '', 'd'}, g.bot)
  g:setGap(3)
  assertEq({'ab', 'c', ''}, g.bot)
  assertEq({'d'},           g.top)
  assertEq('ab\nc\n\nd', tostring(g))
end)

-- test('insert', function()
--   local g = Gap.new()
--   ds.insert(g, 1, {'a', 'b'}, 1)
--   assertEq('a\nb', tostring(g))
--   ds.insert(g, 1, {'c', 'd'})
--   assertEq('a\nc\nd\nb', tostring(g))
-- end)

test('insertstr', function()
  assertEq(1, #Gap.new(''))
  local g = Gap.new(); assertEq(1, #g)
  g:setGap(1)
  assertEq(1, #g); assertEq(1, #g.bot)
  lines.inset(g, 'foo bar', 1, 0)
  assertEq('foo bar', tostring(g))

  lines.inset(g, 'baz ', 1, 5)
  assertEq('foo baz bar', tostring(g))

  lines.inset(g, '\nand', 1, 4)
  assertEq('foo\nand baz bar', tostring(g))
  lines.inset(g, 'buz ', 2, 5)
  assertEq('foo\nand buz baz bar', tostring(g))

  g = Gap.new()
  lines.inset(g, 'foo\nbar', 1, 1)
  assertEq('foo\nbar', tostring(g))
end)

test('remove', function()
  dstest.testLinesRemove(assert(Gap.new))
end)

local function subTests(g)
  assertEq({'ab'},      lines.sub(g, 1, 1))
  assertEq({'ab', 'c'}, lines.sub(g, 1, 2))
  assertEq({'c', ''},   lines.sub(g, 2, 3))
  assertEq('ab\n',      lines.sub(g, 1, 1, 1, 3))
  assertEq('b\nc',      lines.sub(g, 1, 2, 2, 1))
end
test('sub', function()
  local g = Gap.new('ab\nc\n\nd')
  g:setGap(4); subTests(g)
  g:setGap(1); subTests(g)
  g:setGap(2); subTests(g)

  g = Gap.new("4     It's nice to have some real data")
  assertEq('It',     lines.sub(g, 1, 7, 1, 8))
  assertEq("'",      lines.sub(g, 1, 9, 1, 9))
  assertEq("s",      lines.sub(g, 1, 10, 1, 10))
  assertEq(" nice",  lines.sub(g, 1, 11, 1, 15))
end)

test('offset', function()
  local testOffset = dstest.testOffset
  local g = Gap.new(dstest.DATA.offset)
  testOffset(g)
  g:setGap(1); testOffset(g)
  g:setGap(2); testOffset(g)
  g:setGap(4); testOffset(g)
end)

test('find', function()
  local g = Gap.new('12345\n6789\n98765\n')
  assertEq({1, 3}, {lines.find(g, '34', 1, 1)})
  assertEq({2, 1}, {lines.find(g, '67', 1, 3)})
  assertEq({2, 1}, {lines.find(g, '6', 1, 3)})
  assertEq({3, 4}, {lines.find(g, '6', 2, 2)})
end)

test('ipairs', function()
  local g = Gap.new('12345\n6789\n98765\n')
  local t = {}; for i, v in ipairs(g) do
    assertEq(g[i], g:get(i)) t[i] = v
  end
  assertEq({'12345', '6789', '98765', ''}, t)
end)

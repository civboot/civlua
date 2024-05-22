
local lines = require'lines'
local ds = require'ds'
local testing = require'lines.testing'
local test, assertEq, assertMatch, assertErrorPat; ds.auto'civtest'
local Gap = require'lines.Gap'

local tostring = require'metaty'.tostring

test('sub', function()
  local lsub = lines.sub
  local l = lines'ab\nc\n\nd'
  assertEq({'ab'},      lsub(l, 1, 1))
  assertEq({'ab', 'c'}, lsub(l, 1, 2))
  assertEq({'c', ''},   lsub(l, 2, 3))
  assertEq('ab\n',      lsub(l, 1, 1, 1, 3))
  assertEq('ab\n',      lsub(l, 1, 1, 2, 0))
  assertEq('b\nc',      lsub(l, 1, 2, 2, 1))

  l = lines"4     It's nice to have some real data"
  assertEq('It',     lsub(l, 1, 7, 1, 8))
  assertEq("'",      lsub(l, 1, 9, 1, 9))
  assertEq("s",      lsub(l, 1, 10, 1, 10))
  assertEq(" nice",  lsub(l, 1, 11, 1, 15))
end)

test('find', function()
  local t = lines'12345\n6789\n98765\n'
  assertEq({1, 3}, {lines.find(t, '34', 1, 1)})
  assertEq({2, 1}, {lines.find(t, '67', 1, 3)})
  assertEq({2, 1}, {lines.find(t, '6', 1, 3)})
  assertEq({3, 4}, {lines.find(t, '6', 2, 2)})

  assertEq({3, 4}, {lines.findBack(t, '6', 3)})
  assertEq({3, 4}, {lines.findBack(t, '6', 3, 4)})
  assertEq({2, 1}, {lines.findBack(t, '6', 3, 3)})
end)

test('offset', function()
  testing.testOffset(lines(testing.DATA.offset))
end)

test('inset', function()
  local t = {''}
  assertEq(1, #t)
  lines.inset(t, 'foo bar', 1, 0)
  assertEq('foo bar', lines.concat(t))
  lines.inset(t, 'baz ', 1, 5)
  assertEq('foo baz bar', lines.concat(t))

  lines.inset(t, '\nand', 1, 4)
  assertEq('foo\nand baz bar', lines.concat(t))
  lines.inset(t, 'buz ', 2, 5)
  assertEq('foo\nand buz baz bar', lines.concat(t))

  t = {''}
  lines.inset(t, 'foo\nbar', 1, 1)
  assertEq('foo\nbar', lines.concat(t))
end)

test('remove', function()
  testing.testLinesRemove(function(t)
    return type(t) == 'string' and lines(t) or t
  end)
end)

------------------------
-- Gap Tests

test('set', function()
  local g = Gap'ab\nc\n\nd'
  assertEq('ab\nc\n\nd', tostring(g))
  assertEq({'ab', 'c', '', 'd'}, g.bot)
  g:setGap(3)
  assertEq({'ab', 'c', ''}, g.bot)
  assertEq({'d'},           g.top)
  assertEq('ab\nc\n\nd', tostring(g))
end)

-- test('insert', function()
--   local g = Gap()
--   ds.insert(g, 1, {'a', 'b'}, 1)
--   assertEq('a\nb', tostring(g))
--   ds.insert(g, 1, {'c', 'd'})
--   assertEq('a\nc\nd\nb', tostring(g))
-- end)

test('insertstr', function()
  assertEq(1, #Gap'')
  local g = Gap(); assertEq(1, #g)
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

  g = Gap()
  lines.inset(g, 'foo\nbar', 1, 1)
  assertEq('foo\nbar', tostring(g))
end)

test('remove', function()
  testing.testLinesRemove(Gap)
end)

local function subTests(g)
  assertEq({'ab'},      lines.sub(g, 1, 1))
  assertEq({'ab', 'c'}, lines.sub(g, 1, 2))
  assertEq({'c', ''},   lines.sub(g, 2, 3))
  assertEq('ab\n',      lines.sub(g, 1, 1, 1, 3))
  assertEq('b\nc',      lines.sub(g, 1, 2, 2, 1))
end
test('sub', function()
  local g = Gap'ab\nc\n\nd'
  g:setGap(4); subTests(g)
  g:setGap(1); subTests(g)
  g:setGap(2); subTests(g)

  g = Gap"4     It's nice to have some real data"
  assertEq('It',     lines.sub(g, 1, 7, 1, 8))
  assertEq("'",      lines.sub(g, 1, 9, 1, 9))
  assertEq("s",      lines.sub(g, 1, 10, 1, 10))
  assertEq(" nice",  lines.sub(g, 1, 11, 1, 15))
end)

test('offset', function()
  local testOffset = testing.testOffset
  local g = Gap(testing.DATA.offset)
  testOffset(g)
  g:setGap(1); testOffset(g)
  g:setGap(2); testOffset(g)
  g:setGap(4); testOffset(g)
end)

test('find', function()
  local g = Gap'12345\n6789\n98765\n'
  assertEq({1, 3}, {lines.find(g, '34', 1, 1)})
  assertEq({2, 1}, {lines.find(g, '67', 1, 3)})
  assertEq({2, 1}, {lines.find(g, '6', 1, 3)})
  assertEq({3, 4}, {lines.find(g, '6', 2, 2)})
end)

test('ipairs', function()
  local g = Gap'12345\n6789\n98765\n'
  local t = {}; for i, v in ipairs(g) do
    assertEq(g[i], g[i]) t[i] = v
  end
  assertEq({'12345', '6789', '98765', ''}, t)
end)

test('extend', function()
  local g = Gap'123'
  ds.extend(g, {'456', '7'})
  assertEq('123\n456\n7', tostring(g))
end)

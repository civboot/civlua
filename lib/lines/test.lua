
local fmt = require'fmt'
local lines = require'lines'
local ds = require'ds'
local testing = require'lines.testing'
local Gap = require'lines.Gap'
local T = require'civtest'

T.new = function()
  T.eq({'one', 'two 2', ''}, lines'one\ntwo 2\n')
  T.eq({'one', 'two 2', ''}, lines.args'one\ntwo 2\n')
  T.eq({'one', 'two 2', ''}, lines.args('one\n', 'two 2\n'))
end

T.sort = function()
  local sort = lines.sort
  T.eq({1, 1, 2, 2}, {sort(1, 1, 2, 2)})
  T.eq({1, 1, 2, 2}, {sort(2, 2, 1, 1)})
  T.eq({1, 5, 2, 1}, {sort(1, 5, 2, 1)})
  T.eq({1, 5, 2, 1}, {sort(2, 1, 1, 5)})
end

T.sub = function()
  local lsub = lines.sub
  local l = lines'ab\nc\n\nd'
  T.eq({'ab'},      lsub(l, 1, 1))
  T.eq({'ab', 'c'}, lsub(l, 1, 2))
  T.eq({'c', ''},   lsub(l, 2, 3))
  T.eq('ab\n',      lsub(l, 1, 1, 1, 3))
  T.eq('ab\n',      lsub(l, 1, 1, 2, 0))
  T.eq('b\nc',      lsub(l, 1, 2, 2, 1))

  l = lines"4     It's nice to have some real data"
  T.eq('It',     lsub(l, 1, 7, 1, 8))
  T.eq("'",      lsub(l, 1, 9, 1, 9))
  T.eq("s",      lsub(l, 1, 10, 1, 10))
  T.eq(" nice",  lsub(l, 1, 11, 1, 15))
end

T.find = function()
  local t = lines'12345\n6789\n98765\n'
  T.eq({1, 3}, {lines.find(t, '34', 1, 1)})
  T.eq({2, 1}, {lines.find(t, '67', 1, 3)})
  T.eq({2, 1}, {lines.find(t, '6', 1, 3)})
  T.eq({3, 4}, {lines.find(t, '6', 2, 2)})

  T.eq({3, 4}, {lines.findBack(t, '6', 3)})
  T.eq({3, 4}, {lines.findBack(t, '6', 3, 4)})
  T.eq({2, 1}, {lines.findBack(t, '6', 3, 3)})
end

T.offset = function()
  testing.testOffset(lines(testing.DATA.offset))
end

T.inset = function()
  local t = {''}
  T.eq(1, #t)
  lines.inset(t, 'foo bar', 1, 0)
  T.eq('foo bar', lines.join(t))
  lines.inset(t, 'baz ', 1, 5)
  T.eq('foo baz bar', lines.join(t))

  lines.inset(t, '\nand', 1, 4)
  T.eq('foo\nand baz bar', lines.join(t))
  lines.inset(t, 'buz ', 2, 5)
  T.eq('foo\nand buz baz bar', lines.join(t))

  t = {''}
  lines.inset(t, 'foo\nbar', 1, 1)
  T.eq('foo\nbar', lines.join(t))
end

T.remove = function()
  testing.testLinesRemove(function(t)
    return type(t) == 'string' and lines(t) or t
  end)
end

T.box = function()
  local l = lines(
    '1 3 5 7 9\n'
  ..' 2 4 6\n'
  ..'a c d e f g h')
  T.eq({'1 3', ' 2 '        }, lines.box(l, 1,1, 2,3))
  T.eq({' 3 ', '2 4'        }, lines.box(l, 1,2, 2,4))
  T.eq({'7 9', '',   'e f g'}, lines.box(l, 1,7, 3,11))
end

------------------------
-- Gap Tests

T['Gap.set'] = function()
  local g = Gap'ab\nc\n\nd'
  T.eq('ab\nc\n\nd', fmt(g))
  T.eq({'ab', 'c', '', 'd'}, g.bot)
  g:setGap(3)
  T.eq({'ab', 'c', ''}, g.bot)
  T.eq({'d'},           g.top)
  T.eq('ab\nc\n\nd', fmt(g))
end

T['Gap.inset'] = function()
  T.eq(1, #Gap'')
  local g = Gap(); T.eq(0, #g)
  lines.inset(g, 'foo bar', 1, 0)
  T.eq('foo bar', fmt(g))
  g:setGap(1)
  T.eq(1, #g); T.eq(1, #g.bot)

  lines.inset(g, 'baz ', 1, 5)
  T.eq('foo baz bar', fmt(g))

  lines.inset(g, '\nand', 1, 4)
  T.eq('foo\nand baz bar', fmt(g))
  lines.inset(g, 'buz ', 2, 5)
  T.eq('foo\nand buz baz bar', fmt(g))

  g = Gap()
  lines.inset(g, 'foo\nbar', 1, 1)
  T.eq('foo\nbar', fmt(g))
end

T['Gap.remove'] = function()
  testing.testLinesRemove(Gap)
end

local function subTests(g)
  T.eq({'ab'},      lines.sub(g, 1, 1))
  T.eq({'ab', 'c'}, lines.sub(g, 1, 2))
  T.eq({'c', ''},   lines.sub(g, 2, 3))
  T.eq('ab\n',      lines.sub(g, 1, 1, 1, 3))
  T.eq('b\nc',      lines.sub(g, 1, 2, 2, 1))
end
T['Gap.sub'] = function()
  local g = Gap'ab\nc\n\nd'
  g:setGap(4); subTests(g)
  g:setGap(1); subTests(g)
  g:setGap(2); subTests(g)

  g = Gap"4     It's nice to have some real data"
  T.eq('It',     lines.sub(g, 1, 7, 1, 8))
  T.eq("'",      lines.sub(g, 1, 9, 1, 9))
  T.eq("s",      lines.sub(g, 1, 10, 1, 10))
  T.eq(" nice",  lines.sub(g, 1, 11, 1, 15))
end

T['Gap.offset'] = function()
  local testOffset = testing.testOffset
  local g = Gap(testing.DATA.offset)
  testOffset(g)
  g:setGap(1); testOffset(g)
  g:setGap(2); testOffset(g)
  g:setGap(4); testOffset(g)
end

T['Gap.find'] = function()
  local g = Gap'12345\n6789\n98765\n'
  T.eq({1, 3}, {lines.find(g, '34', 1, 1)})
  T.eq({2, 1}, {lines.find(g, '67', 1, 3)})
  T.eq({2, 1}, {lines.find(g, '6', 1, 3)})
  T.eq({3, 4}, {lines.find(g, '6', 2, 2)})
end

T['Gap.ipairs'] = function()
  local g = Gap'12345\n6789\n98765\n'
  local t = {}; for i, v in ipairs(g) do
    T.eq(g[i], g[i]) t[i] = v
  end
  T.eq({'12345', '6789', '98765', ''}, t)
end

T['Gap.extend'] = function()
  local g = Gap'123'
  ds.extend(g, {'456', '7'})
  T.eq('123\n456\n7', fmt(g))
end

T['Gap.write'] = function()
  local g = Gap''
  g:write'hi'; T.eq('hi', fmt(g))
  g:write' there\n'; T.eq('hi there\n', fmt(g))
  g:write'  next\nline'; T.eq('hi there\n  next\nline', fmt(g))
end

T.Writer = function()
  local W = require'lines.Writer'; local w = W{}
  w:write'hi there'
  T.eq(W{'hi there'}, w)
  w:write' bob'
  T.eq(W{'hi there bob'}, w)
  w:write'\nand jane'
  T.eq(W{'hi there bob', 'and jane'}, w)
  w:write' and sue\nand zebe\n'
  T.eq(W{'hi there bob', 'and jane and sue',
             'and zebe', ''}, w)
end

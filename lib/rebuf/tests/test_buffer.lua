METATY_CHECK = true

local pkg = require'pkglib'
local mty = pkg'metaty'
local test, assertEq; pkg'ds'.auto'civtest'

local buffer = pkg'rebuf.buffer'

local tostring = mty.tostring
local Buffer = buffer.Buffer
local C, CS = buffer.Change, buffer.ChangeStart

test('undoIns', function()
  local b = Buffer.new(''); local g = b.gap

  local ch1 = C{k='ins', s='hello ', l=1, c=1}
  local ch2 = C{k='ins', s='world!', l=1, c=7}
  b:changeStart(0, 0)
  local ch = b:insert('hello ', 1, 2)
  assertEq(ch1, ch)
  assertEq('hello ', tostring(g))

  b:changeStart(0, 1)
  ch = b:insert('world!', 1, 7)
  assertEq(ch2, ch)
  assertEq('hello world!', tostring(g))

  -- undo + redo + undo again
  local chs = b:undo()
  assertEq({CS{l1=0, c1=1}, ch2}, chs)
  assertEq('hello ', tostring(g))

  chs = b:redo()
  assertEq({CS{l1=0, c1=1}, ch2}, chs)
  assertEq('hello world!', tostring(g))

  chs = b:undo()
  assertEq({CS{l1=0, c1=1}, ch2}, chs)
  assertEq('hello ', tostring(g))

  -- undo final, then redo twice
  chs = b:undo()
  assertEq({CS{l1=0, c1=0}, ch1}, chs)
  assertEq('', tostring(g))
  b:redo(); chs = b:redo()
  assertEq({CS{l1=0, c1=1}, ch2}, chs)
  assertEq('hello world!', tostring(g))
end)

test('undoInsRm', function()
  local b = Buffer.new(''); local g, ch = b.gap
  local ch1 = C{k='ins', s='12345\n', l=1, c=1}
  local ch2 = C{k='rm', s='12', l=1, c=1}
  b:changeStart(0, 0)
  ch = b:insert('12345\n', 1, 2); assertEq(ch1, ch)

  b:changeStart(0, 1)
  ch = b:remove(1, 1, 1, 2);      assertEq(ch2, ch)
  assertEq('345\n', tostring(g))

  ch = b:undo()[2]                assertEq(ch2, ch)
  assertEq('12345\n', tostring(g))

  ch = b:redo()[2]                assertEq(ch2, ch)
  assertEq('345\n', tostring(g))
end)

test('undoReal', function() -- undo/redo word deleting
  local START = "4     It's nice to have some real data"
  local b = Buffer.new(START); local g, ch = b.gap
  local ch1 = C{k='rm', s='It',  l=1, c=7}
  local ch2 = C{k='rm', s="'",   l=1, c=7}
  local ch3 = C{k='rm', s="'s ", l=1, c=7}
  b:changeStart(0, 0)
  ch = b:remove(1, 7, 1, 8); assertEq(ch1, ch)
  assertEq("4     's nice to have some real data", tostring(g))
  ch = b:remove(1, 7, 1, 7); assertEq(ch2, ch)
  assertEq("4     s nice to have some real data", tostring(g))

  local chs = b:undo();      assertEq({CS{l1=0, c1=0}, ch1, ch2}, chs)
  assertEq("4     It's nice to have some real data", tostring(g))
  ch = b:redo();             assertEq({CS{l1=0, c1=0}, ch1, ch2}, chs)
  assertEq("4     s nice to have some real data", tostring(g))
end)

test('undoMulti', function() -- undo/redo across multi lines
  local START = '123\n456\n789\nabc'
  local b = Buffer.new(START); local g, ch = b.gap
  assertEq(START, tostring(g))
  local ch1 = C{k='rm', s='\n', l=1, c=4}
  local ch2 = C{k='rm', s='\n', l=1, c=7}
  b:changeStart(0, 0)
  ch = b:remove(1, 4, 1, 4); assertEq(ch1, ch)
  assertEq('123456\n789\nabc', tostring(g))
  b:changeStart(0, 0)
  ch = b:remove(1, 7, 1, 7); assertEq(ch2, ch)
  assertEq('123456789\nabc', tostring(g))

  ch = b:undo()[2]                assertEq(ch2, ch)
  assertEq('123456\n789\nabc', tostring(g))

  ch = b:undo()[2]                assertEq(ch1, ch)
  assertEq(START, tostring(g))
end)

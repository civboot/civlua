METATY_CHECK = true

local mty = require'metaty'
local fmt = require'fmt'
local T = require'civtest'.Test

local buffer = require'lines.buffer'

local Buffer = buffer.Buffer
local C, CS = buffer.Change, buffer.ChangeStart

T.undoIns = function()
  local b = Buffer.new(''); local g = b.dat

  local ch1 = C{k='ins', s='hello ', l=1, c=1}
  local ch2 = C{k='ins', s='world!', l=1, c=7}
  b:changeStart(0, 0)
  local ch = b:insert('hello ', 1, 2)
  T.eq(ch1, ch)
  T.eq('hello ', fmt(g))

  b:changeStart(0, 1)
  ch = b:insert('world!', 1, 7)
  T.eq(ch2, ch)
  T.eq('hello world!', fmt(g))

  -- undo + redo + undo again
  local chs = b:undo()
  T.eq({CS{l1=0, c1=1}, ch2}, chs)
  T.eq('hello ', fmt(g))

  chs = b:redo()
  T.eq({CS{l1=0, c1=1}, ch2}, chs)
  T.eq('hello world!', fmt(g))

  chs = b:undo()
  T.eq({CS{l1=0, c1=1}, ch2}, chs)
  T.eq('hello ', fmt(g))

  -- undo final, then redo twice
  chs = b:undo()
  T.eq({CS{l1=0, c1=0}, ch1}, chs)
  T.eq('', fmt(g))
  b:redo(); chs = b:redo()
  T.eq({CS{l1=0, c1=1}, ch2}, chs)
  T.eq('hello world!', fmt(g))
end

T.undoInsRm = function()
  local b = Buffer.new(''); local g, ch = b.dat
  local ch1 = C{k='ins', s='12345\n', l=1, c=1}
  local ch2 = C{k='rm', s='12', l=1, c=1}
  b:changeStart(0, 0)
  ch = b:insert('12345\n', 1, 2); T.eq(ch1, ch)

  b:changeStart(0, 1)
  ch = b:remove(1, 1, 1, 2);      T.eq(ch2, ch)
  T.eq('345\n', fmt(g))

  ch = b:undo()[2]                T.eq(ch2, ch)
  T.eq('12345\n', fmt(g))

  ch = b:redo()[2]                T.eq(ch2, ch)
  T.eq('345\n', fmt(g))
end

T.undoReal = function() -- undo/redo word deleting
  local START = "4     It's nice to have some real data"
  local b = Buffer.new(START); local g, ch = b.dat
  local ch1 = C{k='rm', s='It',  l=1, c=7}
  local ch2 = C{k='rm', s="'",   l=1, c=7}
  local ch3 = C{k='rm', s="'s ", l=1, c=7}
  b:changeStart(0, 0)
  ch = b:remove(1, 7, 1, 8); T.eq(ch1, ch)
  T.eq("4     's nice to have some real data", fmt(g))
  ch = b:remove(1, 7, 1, 7); T.eq(ch2, ch)
  T.eq("4     s nice to have some real data", fmt(g))

  local chs = b:undo();      T.eq({CS{l1=0, c1=0}, ch1, ch2}, chs)
  T.eq("4     It's nice to have some real data", fmt(g))
  ch = b:redo();             T.eq({CS{l1=0, c1=0}, ch1, ch2}, chs)
  T.eq("4     s nice to have some real data", fmt(g))
end

T.undoMulti = function() -- undo/redo across multi lines
  local START = '123\n456\n789\nabc'
  local b = Buffer.new(START); local g, ch = b.dat
  T.eq(START, fmt(g))
  local ch1 = C{k='rm', s='\n', l=1, c=4}
  local ch2 = C{k='rm', s='\n', l=1, c=7}
  b:changeStart(0, 0)
  ch = b:remove(1, 4, 1, 4); T.eq(ch1, ch)
  T.eq('123456\n789\nabc', fmt(g))
  b:changeStart(0, 0)
  ch = b:remove(1, 7, 1, 7); T.eq(ch2, ch)
  T.eq('123456789\nabc', fmt(g))

  ch = b:undo()[2]                T.eq(ch2, ch)
  T.eq('123456\n789\nabc', fmt(g))

  ch = b:undo()[2]                T.eq(ch1, ch)
  T.eq(START, fmt(g))
end

-- Terminal library that supports LAP protocol.
--
-- License CC0 / UNLICENSE (http://github.com/philanc/plterm/issues/4)
-- Originally written 2022 Phil Leblanc, modified 2023 Rett Berg (Civboot.org)
local M = mod and mod'civix.term' or {}

local mty = require'metaty'
local ds  = require'ds'
local d8  = require'ds.utf8'
local char, byte, slen = string.char, string.byte, string.len
local ulen = utf8.len
local push, unpack, sfmt = table.insert, table.unpack, string.format
local io = io
local function getb()
  local b = io.read(1)
  return byte(b)
end
local function min(a, b) return (a<b) and a or b end

local READALL = (_VERSION < "Lua 5.3") and "*a" or "a"
local setrawmode = function()
  return os.execute'stty raw -echo 2> /dev/null'
end
local setsanemode = function() return os.execute'stty sane' end
local savemode = function()
  local fh = io.popen'stty -g'; local mode = fh:read(READALL)
  local succ, e, msg = fh:close()
  return succ and mode or nil, e, msg
end
local restoremode = function(mode) return os.execute('stty '..mode) end

---------------------------------
-- Escape Sequences
local ESC,  LETO, LETR, LBR = 27, byte'O', byte'R', byte'['
local LET0, LET9, LETSC = byte'0', byte'9', byte';'
local INP_SEQ = { -- valid input sequences following '<esc>['
  ['A'] = 'up',    ['B'] = 'down',  ['C'] = 'right', ['D'] = 'left',
  ['2~'] = 'ins',  ['3~'] = 'del',  ['5~'] = 'pgup', ['6~'] = 'pgdn',

  ['11~'] = 'f1',  ['12~'] = 'f2',  ['13~'] = 'f3',  ['14~'] = 'f4',
  ['15~'] = 'f5',  ['17~'] = 'f6',  ['18~'] = 'f7',  ['19~'] = 'f8',
  ['20~'] = 'f9',  ['21~'] = 'f10', ['23~'] = 'f11', ['24~'] = 'f12',

  -- rxv
  ['7~'] = 'home', ['8~'] = 'end',
  -- linux
  ['1~'] = 'home', ['4~'] = 'end',
  ['[1'] = 'f1', ['[2'] = 'f2', ['[3'] = 'f3', ['[4'] = 'f4', ['[5'] = 'f5',
  ['[A'] = 'f1', ['[B'] = 'f2', ['[C'] = 'f3', ['[D'] = 'f4', ['[E'] = 'f5',
  -- xterm
  ['H'] = 'home', ['F'] = 'end',
}
local INP_SEQO = { -- valid input sequences following '<esc>O'
  -- xterm
  ['OP'] = 'f1', ['OQ'] = 'f2', ['OR'] = 'f3', ['OS'] = 'f4',
  -- vt
  ['OH'] = 'home', ['OF'] = 'end',
}
M.INP_SEQ = INP_SEQ; M.INP_SEQO = INP_SEQO

---------------------------------
-- Byte -> Character/Command
local CMD = { -- command characters (not sequences)
  [  9] = 'tab',   [ 13] = 'return',  [ 32] = 'space',
  [127] = 'back',  [ESC] = 'esc',
}
M.CMD = CMD
local ctrlChar = function(c) --> string: key user pressed w/ctrl
  return (c < 32) and char(96+c) or nil
end
local nice = function(c) --> nice key string
  return CMD[c] or (ctrlChar(c) and '^'..ctrlChar(c)) or char(c)
end
M.ctrlChar, M.key = ctrlChar, nice

---------------------------------
-- Terminal Input Stream

-- input(lap.Send): function to be scheduled in a LAP coroutine. Calls send(inp)
-- for each input from the terminal. inp can be either:
-- * a string of utf8.len == 1 for a normal "character" (utf8 codepoint)
-- * a string of utf8.len > 1  for recognized commands (esc, return, etc) and
--   esc sequences (up, down, del, f1, etc).
--
-- See CMD, INP_SEQ, INP_SEQO for possible utf8.len>1 strings.
M.input = function(send)
  local b, s, dat, len = 0, '', {}
  ::continue::
  b = getb()
  ::restart::
  ds.clear(dat)
  len = d8.decodelen(b)
  if len > 1 then
    dat[1] = b; for i=2,len do dat[i]=getb() end
    b = d8.decode(dat)
  end
  if b ~= ESC then send(nice(b)); goto continue end
  while b == ESC do -- get next char, guard against multi-escapes
    b = getb(); if b == ESC then send'esc' end
  end
  if b == LETO then -- <esc>[O, get up to 1 character
    b = getb()
    if INP_SEQO[b] then send(INP_SEQO[b]); goto continue
    else goto restart end
  end
  if b ~= LBR then goto restart end
  -- get up to three characters and try to find in
  -- INP_SEQ. If c is not visible ASCII then bail early
  s = ''
  for i=1,3 do
    b = getb(); if b <= 0x20 or b > 0x7F then break end
    s = s..char(b)
    if INP_SEQ[s] then send(INP_SEQ[s]); goto continue end
    dat[i] = b; b = nil
  end
  if s:match'%d+;?%d*' then
    for i=4,8 do -- could be size: <esc>[<int>;<int>R
      b = getb(); if b <= 0x20 or b > 0x7F then break end
      if b == LETR then
        local h, w = char(unpack(dat)):match'(%d+);(%d+)'
        if h then
          send{'size', h=tonumber(h), w=tonumber(w)}
        end
        goto continue
      end
      dat[i] = b; b = nil
    end
  end
  for _, d in ipairs(dat) do
    send(nice(dat[i]))
  end
  if b then goto restart else goto continue end
  error'unreachable'
end

---------------------------------
-- Terminal Control Functions
M.termFn = function(name, fmt)
  local fmt = '\027['..fmt
  return function(...) io.write(fmt:format(...)) end
end
for name, fmt in pairs{
  clear = '2J',       cleareol= 'K',
  -- color(0) resets; colorFB(foreground,background)
  color = '%im',      colorFB = '%i;%im',
  -- cursor control
  up='%iA',      down='%iB',  right='%iC', left='%iD',
  golc='%i;%iH', hide='?25l', show='?25h',
  save='s',      restore='u', reset='c',
  getlc='6n',
} do M[name] = M.termFn(name, fmt) end

M.colors = {
  default = 0,
  black   = 30, red     = 31, green   = 32,  yellow = 33,
  blue    = 34, magenta = 35, cyan    = 36,  white = 37,
}
M.bgcolors = {
  black = 40,   red     = 41, green = 42,    yellow = 43,
  blue  = 44,   magenta = 45, cyan = 46,     white = 47,
}

-- causes input to (eventually) send {'size', l=, c=}
M.size = function()
  M.save(); M.down(999); M.right(999)
  M.getlc(); M.restore(); io.flush()
end

M.ATEXIT = {}
M.exitRawMode = function()
  local mt = getmetatable(M.ATEXIT); assert(mt)
  mt.__gc()
  setmetatable(M.ATEXIT, nil)
  local stdout = M.ATEXIT.stdout
  io.stdout = stdout
  io.stderr = M.ATEXIT.stderr
  io.stderr:write'!! finished atexit\n'
end
M.enterRawMode = function(stdout, stderr, enteredFn, exitFn)
  assert(stdout, 'must provide new stdout')
  assert(stderr, 'must provide new stderr')
  assert(not getmetatable(M.ATEXIT))
  local SAVED, ok, msg = savemode()
  assert(ok, msg); ok, msg = nil, nil
  local mt = {
    __gc = function()
      if not getmetatable(M.ATEXIT) then return end
      M.clear()
      restoremode(SAVED)
      if exitFn then exitFn() end
   end,
  }
  setmetatable(M.ATEXIT, mt)
  M.ATEXIT.stdout = io.stdout; M.ATEXIT.stderr = io.stderr
  -- io.output(stdout)
  io.stdout = stdout
  io.stderr = stderr
  setrawmode(); if enteredFn then enteredFn() end
end

-- Global Term object which actually controls the input terminal.
M.Term = {
  h=-1, w=-1, l=-1, c=-1,
  flush    = function()        io.flush()                    end,
  clear    = function(t)       M.clear();    t.l, t.c = 1, 1 end,
  golc     = function(t, l, c) M.golc(l, c); t.l, t.c = l, c end,
  cleareol = function(t, l, c)
    if l and c then t:golc(l, c) end
    M.cleareol()
  end,
  write = function(t, s)
    io.write(s)
    t.c = min(t.w, t.c + slen(s))
  end,
  -- TODO: remove golc here. Just write.
  set = function(t, l, c, char) -- term:set(l, c, 'f')
    t:golc(l, c); io.write(char)
    t.c = min(t.w, t.c + 1)
  end,
  size = M.size,
}

--------------------------------
-- Validation and Interaction
-- These help with validating keys are valid and converting
-- special keys (return, space, etc) to their literal form.

M.LITERALS = {
  ['tab']       = '\t',
  ['return']    = '\n',
  ['space']     = ' ',
  ['slash']     = '/',
  ['backslash'] = '\\',
  ['caret']     = '^',
}

-- Convert any key to it's literal form
-- [#
--   literal'a'       -> 'a'
--   literal'return'  -> '\n'
--   literal'invalid' -> nil
-- ]#
M.literal = function(key) --> literalstring?
  return (1 == ulen(key)) and key or M.LITERALS[key]
end

local VK = {}
for c=byte'a', byte'z' do VK['^'..char(c)]  = true end
-- m and i don't have ctrl variants
VK['^m'] = 'ctrl+m == return'
VK['^i'] = 'ctrl+i == tabl'
for c     in pairs(M.LITERALS)    do VK[c]  = true end
for _, kc in pairs(M.CMD)         do VK[kc] = true end
for _, kc in pairs(M.INP_SEQ)     do VK[kc] = true end
for _, kc in pairs(M.INP_SEQO)    do VK[kc] = true end
M.VALID_KEY = VK

-- Check that a key is valid. Return errstring if not.
M.keyError = function(key) --> errstring?
  if #key == 0 then return 'empty key' end
  local v = VK[key]; if v then
    return (v ~= true) and sfmt('%q not valid key: %s', key, v) or nil
  end
  if #key == 1 then; local cp = byte(key)
    if cp <= 32 or (127 <= cp and cp <= 255) then
      return sfmt('key %q not a printable character', key)
    end
    return
  end
  if ulen(key) ~= 1 then
    return sfmt('invalid key: %q', key)
  end
end
M.checkKey = function(key) --> key?, errstring?
  local err = M.keyError(key); if err then return nil, err end
  return key
end

--------------------------------
-- Test Helpers

-- An in-memory fake terminal that you can assert against
M.FakeTerm = mty'FakeTerm'{
  'h[int]: height', 'w[int]: width',
  'l[int]: line',   'c[int]: column',
}
getmetatable(M.FakeTerm).__call = function(T, h, w)
  local t = mty.construct(T, {h=assert(h), w=assert(w)})
  t:clear()
  return t
end
-- set items to left of t.l to space if they are empty
M.FakeTerm._fill = function(t, l, c)
  local line = t[l or t.l]
  for i = #line+1, (c or t.c) - 1 do line[i] = ' ' end
end
M.FakeTerm.flush = ds.noop
M.FakeTerm.start = ds.noop
M.FakeTerm.stop  = ds.noop
M.FakeTerm.clear = function(t)
  t:golc(1, 1)
  for l=1,t.h do
    t[l] = t[l] or {}; ds.clear(t[l])
  end
end
M.FakeTerm.golc = function(t, l, c)
  t:assertLC(l, c); t.l, t.c = l, c end
M.FakeTerm.cleareol = function(t, l, c)
  if l and c then t:golc(l, c) end
  local c, line = t.c, t[t.l]
  ds.clear(line, c, #line - c + 1)
end
M.FakeTerm.size = ds.noop
M.FakeTerm.set = function(t, l, c, char)
  t:assertLC(l, c)
  assert(char); assert(utf8.len(char) == 1)
  t:_fill(l, c)
  t[l][c] = char
end
M.FakeTerm.write = function(t, s)
  if #s == 0 then return end
  t:assertLC(t.l, t.c + #s - 1)
  t:_fill()
  local line = t[t.l]
  for i=1, #s do line[t.c + i - 1] = s:sub(i,i) end
  t.c = t.c + #s
end
M.FakeTerm.assertLC = function(t, l, c) -- utility for testing
  if l < 1 or l > t.h then error("line OOB: "..l) end
  if c < 1 or c > t.w then error("col OOB: "..c) end
end
M.FakeTerm.__fmt = function(t, f)
  for i, line in ipairs(t) do
    push(f, table.concat(line))
    if i < #t then push(f, '\n') end
  end
end

return M

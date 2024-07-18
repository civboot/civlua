-- Civboot vt100 Terminal library that supports LAP protocol.
--
-- License CC0 / UNLICENSE
-- Originally written 2022 Phil Leblanc, modified 2023 Rett Berg (Civboot.org)
-- Authorized for relicense in: http://github.com/philanc/plterm/issues/4
local M = mod and mod'vt100' or {}

local mty = require'metaty'
local ds  = require'ds'
local Grid = require'ds.Grid'
local log = require'ds.log'
local d8  = require'ds.utf8'

local min = math.min
local char, byte, slen = string.char, string.byte, string.len
local lower            = string.lower
local ulen = utf8.len
local push, unpack, sfmt = table.insert, table.unpack, string.format
local io = io

-- VT100 Terminal Emulator
--   Write the text to display
--   Write the foreground/background colors to fg/bg
--   Then call :draw() to draw to terminal.
--
-- Requires vt100.start() have been called to initiate raw mode.
M.Term = mty'Term'{
  'l [int]: cursor line', 'c [int]: cursor column', l=1, c=1,
  'h [int]: height', 'w [int]: width', h=40, w=80,
  'text [ds.Grid]: the text to display',
  'fg   [ds.Grid]: foreground color (ASCII coded)',
  'bg   [ds.Grid]: background color (ASCII coded)',
  '_waiting [thread]: the thread waiting on update (i.e. size)',
  'run [boolean]: set to false to stop coroutines', run=true,
}
getmetatable(M.Term).__call = function(T, t)
  t = mty.construct(T, t)
  t.text     = Grid{h=t.h, w=t.w}
  t.fg, t.bg = Grid{h=t.h, w=t.w}, Grid{h=t.h, w=t.w}
  t:_updateChildren(); t:clear()
  return t
end

M.Term._updateChildren = function(tm)
  local h, w = tm.h, tm.w
  tm.text.h, tm.fg.h, tm.bg.h = h, h, h
  tm.text.w, tm.fg.w, tm.bg.w = w, w, w
end

M.Term.clear = function(tm)
  tm.text:clear(); tm.fg:clear(); tm.bg:clear()
end

M.Term.__fmt = function(tm, fmt) return tm.text:__fmt(fmt) end


---------------------------------
-- CONSTANTS (and working with them)

-- ASCII Color table.
-- This allows applications to set single characters in a Grid and
-- have it map to a color (which is looked up in Fg/Bg Color)
M.AsciiColor = { -- ASCII color definitions
  z = 'default', [' '] = 'default',
  w = 'white', l = 'lgrey',  d = 'dgrey', p = 'black', -- p == "pitch"
  r = 'red',   y = 'yellow', g = 'green', c = 'cyan',
	b = 'blue',  m = 'magenta',
}

M.FgColor = { -- foreground
  default = 39, lgrey   = 37, dgrey   = 90,
  black   = 30, red     = 31, green   = 32, yellow = 33,
  blue    = 34, magenta = 35, cyan    = 36, white = 97,
}
M.BgColor = { -- background
	default = 49, lgrey   = 47, dgrey   = 100,
  black   = 40, red     = 41, green   = 42, yellow = 43,
  blue    = 44, magenta = 45, cyan    = 46, white = 107,
}

M.fgColor = function(c) --> colorCode
  return M.FgColor[M.AsciiColor[lower(c or 'z')]]
end
M.bgColor = function(c) --> colorCode
  return M.BgColor[M.AsciiColor[lower(c or 'z')]]
end

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

-------------
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

---------------------------------
-- Terminal Control (functions)

M.ctrl = mod and mod'vt100.ctrl' or {}

local termFn = function(name, fmt)
  local fmt = '\027['..fmt
  return function(...) io.write(fmt:format(...)) end
end
for name, fmt in pairs{
  clear = '2J',       cleareol= 'K',
  -- color(0) resets; colorFB(foreground,background)
  color = '%im',      colorFB = '%i;%im',
  -- cursor control
  nextline = 'E',
  up='%iA',      down='%iB',  right='%iC', left='%iD',
  golc='%i;%iH', hide='?25l', show='?25h',
  save='s',      restore='u', reset='c',
  getlc='6n',
} do M.ctrl[name] = termFn(name, fmt) end

-- causes terminal to send size as (escaped) cursor position
M.ctrl.size = function()
  local C = M.ctrl
  C.save(); C.down(999); C.right(999)
  C.getlc(); C.restore(); io.flush()
end

-------------------
-- Actual VT100 Control Methods
local function getb()
  local b = byte(io.read(1))
  -- log.trace('input %s %q', b, char(b))
  return b
end

-- send a request for size which input() will receive and
-- call _ready()
M.Term._requestSize = function(tm)
  tm._waiting = coroutine.running(); M.ctrl.size()
end

M.Term._ready = function(tm, msg)
  LAP_READY[assert(tm._waiting)] = msg or true
  tm._waiting = nil
end

-- This can only be run with an active (LAP) input coroutine
M.Term.resize = function(tm)
  tm:_requestSize()
  while tm._waiting do coroutine.yield'forget' end -- wait for size
  tm:_updateChildren(); tm:clear() -- clear updates rows
end

-- function to run in a (LAP) coroutine.
-- Requires the input coroutine to also be run for reading the size escape.
M.Term.draw = function(tm)
  log.trace'drawing'
  local golc, nextline = M.ctrl.golc, M.ctrl.nextline
  local colorFB        = M.ctrl.colorFB
  local fgC, bgC       = M.fgColor, M.bgColor
  M.ctrl.hide(); M.ctrl.clear()     -- hide cursor and clear screen
  golc(1, 1)
	local fg, bg
  -- fill text
  for l=1,tm.text.h do
    for c=1,tm.text.w do
      local chr = tm.text[l][c]; if not chr then break end
      local f, b = tm.fg[l][c], tm.bg[l][c]
      if f ~= fg or b ~= bg then
        fg, bg = f, b; colorFB(fgC(f), bgC(b))
      end
      io.write(chr)
    end
    nextline()
  end
  M.ctrl.color(0)
  golc(tm.l, tm.c); M.ctrl.show() -- set cursor and show it
  io.flush()
end

-- function to run in a (LAP) coroutine.
-- send() is called with each key recieved. Typically this is a lap.Send.
M.Term.input = function(tm, send) --> infinite loop (run in coroutine)
  local b, s, dat, len = 0, '', {}
  ::continue::
  if not tm.run then return end
  b = getb()
  ::restart::
  ds.clear(dat)
  len = d8.decodelen(b)
  if len > 1 then
    dat[1] = b; for i=2,len do dat[i]=getb() end
    b = d8.decode(dat)
  end
  if b ~= ESC then
    b = nice(b); log.trace('send %q', b)
    send(b); goto continue
  end
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
        if h and tm._waiting then
          tm.h, tm.w = tonumber(h), tonumber(w)
          tm:_ready'size updated'
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

-------------------
-- start / stop raw mode
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

M.ATEXIT = {}
M.stop = function()
  local mt = getmetatable(M.ATEXIT); assert(mt)
  mt.__gc()
  setmetatable(M.ATEXIT, nil)
  local stdout = M.ATEXIT.stdout
  io.stdout = stdout
  io.stderr = M.ATEXIT.stderr
  log.info'vt100.stop() complete'
end
M.start = function(stdout, stderr, enteredFn, exitFn)
  log.info'vt100.start() begin'
  assert(stdout, 'must provide new stdout')
  assert(stderr, 'must provide new stderr')
  assert(not getmetatable(M.ATEXIT))
  local SAVED, ok, msg = savemode()
  assert(ok, msg); ok, msg = nil, nil
  local mt = {
    __gc = function()
      if not getmetatable(M.ATEXIT) then return end
      M.ctrl.clear()
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
  log.info'vt100.start() complete'
end

return M

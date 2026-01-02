local G = G or _G
--- Civboot vt100 Terminal library that supports LAP protocol.
--- Module for interacting with the vt100 via keys and AsciiColors.
--- [##
--- License CC0 / UNLICENSE
--- Originally written 2022 Phil Leblanc, modified 2023 Rett Berg (Civboot.org)
--- Authorized for relicense in: http://github.com/philanc/plterm/issues/4
--- ]##
local M = G.mod and mod'vt100' or setmetatable({}, {})
G.MAIN = G.MAIN or M

local mty = require'metaty'
local fmt = require'fmt'
local shim = require'shim'
local ds  = require'ds'
local Grid = require'ds.Grid'
local log = require'ds.log'
local d8  = require'ds.utf8'
local ac = require'asciicolor'

local min = math.min
local char, byte, slen = string.char, string.byte, string.len
local lower, upper     = string.lower, string.upper
local ulen = utf8.len
local push, unpack, sfmt = table.insert, table.unpack, string.format
local concat             = table.concat
local io = io
local isup, islow = ds.isupper, ds.islower
local acode = ac.assertcode

local ty = mty.ty

--- Direct terminal control functions
local ctrl = mod and mod'vt100.ctrl' or {}
M.ctrl = ctrl

local DEFAULT = {[''] = true, [' '] = true, z=true}
local RESET, BOLD, UL, INV = 0, 1, 4, 7

--- VT100 Terminal Emulator [+
--- * Write the text to display
--- * Write the foreground/background colors to fg/bg
--- * Then call :draw() to draw to terminal.
--- ]
---
--- Requires [$vt100.start()] have been called to initiate raw mode.
M.Term = mty'Term'{
  'fd [file]: file to write output to in draw()',
  'l [int]: cursor line', 'c [int]: cursor column', l=1, c=1,
  'h [int]: height', 'w [int]: width', h=40, w=80,
  'text [ds.Grid]: the text to display',
  'fg   [ds.Grid]: foreground color (ASCII coded)',
  'bg   [ds.Grid]: background color (ASCII coded)',
  '_waiting [thread]: the thread waiting on update (i.e. size)',
  'run [boolean]: set to false to stop coroutines', run=true,
  'styler [asciicolor.Styler]: optional styler',
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

-- Escape Sequences
local ESC,  LETO, LETR, LBR = 27, byte'O', byte'R', byte'['
local LET0, LET9, LETSC = byte'0', byte'9', byte';'
--- valid input sequences following [#<esc>[]#
M.INP_SEQ = {
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
--- valid input sequences following [#<esc>O]#
M.INP_SEQO = {
  -- xterm
  P = 'f1', Q = 'f2', R = 'f3', S = 'f4',
  -- vt
  H = 'home', F = 'end',
}
local INP_SEQ, INP_SEQO = M.INP_SEQ, M.INP_SEQO

-------------
-- Byte -> Character/Command
local CMD = { -- command characters (not sequences)
  [  9] = 'tab',   [ 13] = 'enter',  [ 32] = 'space',
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
--- These help with validating keys are valid and converting
--- special keys (return, space, etc) to their literal form.
M.LITERALS = {
  ['tab']       = '\t',
  ['enter']     = '\n',
  ['space']     = ' ',
  ['slash']     = '/',
  ['backslash'] = '\\',
  ['caret']     = '^',
}

--- Convert any key to it's literal form [#
---   literal'a'       -> 'a'
---   literal'enter'   -> '\n'
---   literal'esc'     -> nil
--- ]#
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

--- Check that a key is valid. Return errstring if not.
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

local termFn = function(name, fmt)
  local fmt = '\027['..fmt
  return function(f, ...) return f:write(fmt:format(...)) end
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
} do ctrl[name] = termFn(name, fmt) end
local rawcolor, rawcolorFB = ctrl.color, ctrl.colorFB
local cleareol             = ctrl.cleareol
local golc, nextline       = ctrl.golc, ctrl.nextline

--- causes terminal to send size as (escaped) cursor position
ctrl.size = function(f)
  local C = ctrl
  C.save(f); C.down(f, 999); C.right(f, 999)
  C.getlc(f); C.restore(f)
end

---------------------------------
-- asciicolor constants and functions

--- Foreground Terminal Codes
M.FgColor = {
  zero    = 39,
  -- (dark)       (light)
  black    = 30,  white     = 97,
  darkgrey = 90,  lightgrey = 37,
  red      = 31,  pink      = 91,
  green    = 32,  tea       = 92,
  yellow   = 33,  honey     = 93,
  cyan     = 36,  aqua      = 96,
  navy     = 34,  sky       = 94,
  magenta  = 35,  fuschia   = 95,
}
--- Background Terminal Codes
M.BgColor = {
  zero    = 49,
  -- (dark)       (light)
  black    = 40,  white     = 107,
  darkgrey = 100, lightgrey = 47,
  red      = 41,  pink      = 101,
  yellow   = 43,  honey     = 103,
  green    = 42,  tea       = 102,
  cyan     = 46,  aqua      = 106,
  navy     = 44,  sky       = 104,
  magenta  = 45,  fuschia   = 105,
}
--- Style Terminal Codes
M.Style = {
  reset = RESET, bold = BOLD, underline = UL,
  invert = INV, -- invert fg/bg
}

--- asciicolor code -> vt100 code
M.Fg, M.Bg = ds.TypoSafe{}, ds.TypoSafe{}
for code, name in pairs(ac.Color) do
  M.Fg[code]        = M.FgColor[name]
  M.Fg[upper(code)] = M.FgColor[name]
  M.Bg[code]        = M.BgColor[name]
  M.Bg[upper(code)] = M.BgColor[name]
end
local Fg, Bg = M.Fg, M.Bg

--- Set the color, taking into account the previous color
M.colorFB = function(f, fg, bg, fg0, bg0)
  local bold,     bold0,     ul,       ul0 =
        isup(fg), isup(fg0), isup(bg), isup(bg0)
  if (bold ~= bold0) or (ul ~= ul0) then
    rawcolor(f, 0) -- clear bold/underline
    if bold then rawcolor(f, BOLD) end
    if ul   then rawcolor(f, UL)   end
    if (fg == 'z') and (bg == 'z') then return end -- plain
  end
  return rawcolorFB(f, assert(Fg[fg]), assert(Bg[bg]))
end

--- write to the terminal-like file f using colors fgstr and bgstr
--- accounting for previous color codes fg, bg
---
--- Additional strings (...) are written using plain color.
---
--- Return: [$fg, bg, write(str, ...)]
--- [" Note: fg and bg are the updated color codes]
M.acwrite = function(f, colorFB, fg, bg, fgstr, bgstr, str, ...)
  str, fgstr, bgstr = str or '', fgstr or '', bgstr or ''
  local w1, w2, si, slen, chr, fc, bc = true, nil, 1, #str
  for i=1,slen do
    chr, fc, bc = str:sub(i,i), fgstr:sub(i,i), bgstr:sub(i,i)
    fc, bc = acode(fc), acode(bc)
    if fc ~= fg or bc ~= bg then
      f:write(str:sub(si, i-1)) -- write in previous color
      w1, w2 = colorFB(f, fc, bc, fg, bg)
      si, fg, bg = i, fc, bc
    end
  end
  if slen - si >= 0 then f:write(str:sub(si)) end -- write end of string
  if select('#', ...) > 0 then -- write(...) using color=z
    if fg ~= 'z' or bg ~= 'z' then
      colorFB(f, 'z', 'z', fg, bg)
      fg, bg = 'z', 'z'
    end
    w1, w2 = f:write(...)
  end
  return fg, bg, w1, w2
end
local colorFB, acwrite = M.colorFB, M.acwrite

-------------------
-- Actual VT100 Control Methods
local function getb()
  local b = byte(io.read(1)); -- log.trace('input %s %q', b, char(b))
  return b
end

--- send a request for size.
--- Note: the input() coroutine will receive and call _ready()
M.Term._requestSize = function(tm)
  tm._waiting = coroutine.running(); ctrl.size(tm.fd)
end
M.Term._ready = function(tm, msg)
  LAP_READY[assert(tm._waiting)] = msg or true
  tm._waiting = nil
end

--- request size and clear children
--- This can only be run with an active (LAP) input coroutine
M.Term.resize = function(tm)
  tm:_requestSize()
  while tm._waiting do coroutine.yield'forget' end -- wait for size
  tm:_updateChildren(); tm:clear() -- note: clear updates row length
end

--- draw the text and color(fg/bg) grids to the screen
M.Term.draw = function(tm)
  local fd = tm.fd
  local w, h, fg, bg, ok, err = tm.text.w, tm.text.h
  ctrl.hide(fd); golc(fd, 1,1)
  for l=1,h  do
    local txt = concat(tm.text[l])
    fg, bg, ok, err = acwrite(fd, colorFB, 'z', 'z',
      concat(tm.fg[l]), concat(tm.bg[l]), txt)
    if fg ~= 'z' or bg ~= 'z' then ctrl.color(fd, 0) end
    if #txt < w               then cleareol(fd)      end
    if l < h                  then fd:write'\r\n'    end
  end
  golc(fd, tm.l, tm.c); ctrl.show(fd) -- set cursor and show it
end

--- function to run in a (LAP) coroutine.
--- [$send()] is called with each key recieved. Typically this is a lap.Send.
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
    b = nice(getb()); local s = INP_SEQO[b]
    if s then send(s);            goto continue
    else      send'esc'; send(b); goto restart end
  end
  if b ~= LBR then send'esc'; goto restart end
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
  send'esc'; send'['
  for _, d in ipairs(dat) do send(nice(d)) end
  if b then goto restart else goto continue end
  error'unreachable'
end

-------------------
-- start / stop raw mode
local READALL = (_VERSION < "Lua 5.3") and "*a" or "a"
M.setrawmode = function()
  return os.execute'stty raw -echo 2> /dev/null'
end
M.setsanemode = function() return os.execute'stty sane' end
M.savemode = function() --> mode?, errmsg?
  local fh = io.popen'stty -g'; local mode = fh:read(READALL)
  local ok, e, msg = fh:close()
  return ok and mode or nil, msg
end
M.restoremode = function(mode) return os.execute('stty '..mode) end

M.start = function() --> savedmode
  local sm = M.savemode()
  M.setrawmode()
  return sm
end
M.stop = function(fd, savedmode)
  assert(fd and savedmode, 'must pass in fd and savedmode')
  ctrl.clear(fd)
  ctrl.show(fd)
  M.restoremode(savedmode)
end

--- create a Fmt with sensible defaults from the config
M.Fmt = function(t)
  assert(t.to, 'must set to = the output')
  if t.style == nil then t.style = shim.getEnvBool'COLOR' end
  if t.style or (t.style==nil) and fmt.TTY[t.to] then
    t.style, t.to = true, ac.Styler {
      acwriter = require'vt100.AcWriter'{f=t.to},
      style = ac.loadStyle(),
    }
  end
  return fmt.Fmt(t)
end

--- Listens to keyboard inputs and echoes them.
M.main = function(args)
  local epath = '/tmp/vt100.err'
  print('vt100 echo, use ^c (cntrl+c) to quit. stderr at', epath)
  M.start(assert(io.open(epath, 'a')))
  local te = {
    run=true,
    _ready=function() print'term resized\r' end,
  }
  local send = function(b)
    print(('received %q\r'):format(b))
    if b == '^c' then te.run = false end
  end
  M.Term.input(te, send)
  M.stop()
  print'^c stopped, done'
end



--- The recommended setup function, enables color in the terminal in civstack
--- libraries (and those that adhere to them).
M.setup = function(args)
  if G.IS_SETUP then return end
  args = args or {}
  io.user = M.Fmt{to=assert(shim.file(rawget(args, 'to'),  io.stdout))}
  -- io.fmt  = M.Fmt{to=assert(shim.file(rawget(args, 'log'), io.stderr))}
  io.fmt  = M.Fmt{to=io.stderr}
  G.IS_SETUP = true
end

return M

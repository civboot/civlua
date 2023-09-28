
local mty = require'metaty'
local ds = require'ds'
local civix = require'civix'

local yield, stdin = coroutine.yield, io.stdin
local char, byte   = string.char, string.byte
local function getb() return string.byte(stdin:read(1)) end
local function outf(...) stdin:write(...); stdin:flush() end

local READALL = (_VERSION < "Lua 5.3") and "*a" or "a"
local setrawmode = function()
  return os.execute('stty raw -echo 2> /dev/null\n')
end
local setsanemode = function() return os.execute('stty sane') end
local savemode = function()
  local fh = io.popen("stty -g\n"); local mode = fh:read(READALL)
  local succ, e, msg = fh:close()
  return succ and mode or nil, e, msg
end
local restoremode = function(mode) return os.execute('stty '..mode) end

local M = {}

---------------------------------
-- UTF8 Stream Handling
if utf8 then
  char = utf8.char
  -- lenRemain, mask for decoding first byte
  local u1 = {1, 0x7F}; local u2 = {2, 0x1F}
  local u3 = {3, 0x0F}; local u4 = {4, 0x07}
  local U8MSK = {} -- Get {len,msk} via U8MSK[0xF8 & firstByte]
  for b=0,15 do U8MSK[        b << 3 ] = u1 end -- 0xxxxxxx: 1byte utf8
  for b=0,3  do U8MSK[0xC0 | (b << 3)] = u2 end -- 110xxxxx: 2byte utf8
  for b=0,1  do U8MSK[0xE0 | (b << 3)] = u3 end -- 1110xxxx: 3byte utf8
                U8MSK[0xF0           ] = u4     -- 11110xxx: 4byte utf8

  -- decode utf8 data into an integer.
  -- Use utf8.char to turn into a string.
  local function u8decode(lenMsk, c, rest)
    c = lenMsk[2] & c
    for i=1,lenMsk[1]-1 do c = (c << 6) | (0x3F & rest[i]) end
    return c
  end
  M.U8MSK = U8MSK; M.u8decode = u8decode
end

---------------------------------
-- Escape Sequences
local ESC,  LETO, LETR, LBR = 27, byte'O', byte'R', byte'['
local INP_SEQ = { -- valid input sequences following '<esc>['
  ['A'] = 'up',   ['B'] = 'down',  ['C'] = 'right',  ['D'] = 'left',
  ['2~'] = 'ins', ['3~'] = 'del',  ['5~'] = 'pgup',  ['6~'] = 'pgdn',

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
  --[[xterm]] ['OP'] = 'f1', ['OQ'] = 'f2', ['OR'] = 'f3', ['OS'] = 'f4',
  --[[vt]]    ['OH'] = 'home', ['OF'] = 'end',
}

---------------------------------
-- Byte -> Character/Command
local CMD = { -- command characters (not sequences)
  [  9] = 'tab',   [ 13] = 'return',  [ 32] = 'space',
  [127] = 'back',  [ESC] = 'esc',
}
local function ctrlChar(c) -- Note: excludes CMD
  if c >= 32 then return nil end
  return char(64+c) -- TODO: use 96 for lower-case
end
local function nice(c)
  if     CMD[c]      then return CMD[c]
  elseif ctrlChar(c) then return '^'..ctrlChar(c) end
  return char(c)
end

---------------------------------
-- Terminal Input Stream

-- Get raw bytes from input
M.rawinput = function() return coroutine.wrap(function()
    while true do yield(getb()) end
end) end--rawinput()

-- Get nice input from the terminal. This returns either:
-- * a string of utf8.len== 1 for a normal "character" (utf8 codepoint)
-- * a string of utf8.len > 1  for recognized commands (esc, return, etc) and
--   esc sequences (up, down, del, f1, etc).
--
-- See CMD, INP_SEQ, INP_SEQO for possible len>1 strings.
M.niceinput = function() return coroutine.wrap(function()
  local b, s, dat, len = 0, '', {}
  ::continue::
  b = getb()
  ::restart::
  if utf8 then
    local lenMsk = U8MSK[0xF8 & b]
    if lenMsk[1] > 1 then
      dat[1] = b; for i=2,lenMsk[1] do dat[i]=getb() end
      b = u8decode(lenMsk, b, dat)
    end
  end
  if b ~= ESC then yield(nice(b)); goto continue end
  while b == ESC do -- get next char, guard against multi-escapes
    b = getb(); if b == ESC then yeild('esc') end
  end
  if b == LETO then -- <esc>[O, get up to 1 character
    b = getb()
    if INP_SEQO[b] then yield(INP_SEQO[b]); goto continue
    else goto restart end
  end
  if b ~= LBR then goto restart end
  -- get up to three characters and try to find in
  -- INP_SEQ. If c is not visible ASCII then bail early
  len, s = 0, ''
  for i=1,3 do
    b = getb(); if 0x20 <= b or b > 0x7F then break end
    s = s..char(b)
    if INP_SEQ[s] then yield(INP_SEQ[s]); goto continue end
    dat[i] = b; len = i; b = nil
  end
  for i=1,len do yield(nice(dat[i])) end
  if b then goto restart else goto continue end
end) end

---------------------------------
-- Terminal Control Functions

M.termFn = function(fmt)
  fmt = '\027['..fmt; return function(...)
    return string.format(fmt, ...)
  end
end
for name, fmt in ipairs({
  clear = '2J',       cleareol= 'K',
  -- color(0) resets; colorFB(foreground,background)
  color = '%im',      colorFB = '%i;%im',
  -- golc(line,col). up(1), etc. All are for cursor
  up='%iA',      down='%iB',  right='%iC', left='%iD',
  golc='%i;%iH', hide='?25l', show='?25h',
  save='s',      restore='u', reset='c',
}) do M[name] = M.termFn(name) end

M.colors = {
  default = 0,
  black   = 30, red     = 31, green   = 32,  yellow = 33,
  blue    = 34, magenta = 35, cyan    = 36,  white = 37,
}
M.bgcolors = {
  black = 40,   red     = 41, green = 42,    yellow = 43,
  blue  = 44,   magenta = 45, cyan = 46,     white = 47,
}

M.getlc = function()
  local s, c = {}, nil
  outf('\027[6n')
  c = getb(); if c ~= ESC then return nil end
  c = getb(); if c ~= LBR then return nil end
  for _=1,8 do
    c = getb(); if c == LETR then break end
    table.insert(s, c)
  end
  local l, c = char(table.unpack(s)):match'(%d+);(%d+)'
  if not l then return end
  return tonumber(l), tonumber(c)
end

M.size = function()
  M.save(); M.down(999); M.right(999)
  local h, w = M.getlc(); M.restore()
  return h, w
end

M.ATEXIT = {}
M.enterRawMode = function(enteredFn, exitFn)
  assert(not getmetatable(M.ATEXIT))
  local SAVED, err, msg = M.savemode()
  assert(err, msg); err, msg = nil, nil
  local mt = {
    __gc = function()
      M.clear()
      restoremode(SAVED)
      io.stdout = stdout
      io.stderr = stderr
      if exitFn then exitFn() end
   end,
  }
  setmetatable(M.ATEXIT, mt)
  io.stdout = stdoutF
  io.stderr = stdoutF
  mty.pnt('Entering raw mode')
  setrawmode(); if enteredFn then enteredFn() end
end
M.exitRawMode = function()
  local mt = getmetatable(M.ATEXIT); assert(mt)
  mt.__gc()
  setmetatable(M.ATEXIT, nil)
end

-- Term object
-- This is an interface which other terminal implementations can copy.
-- For example, creating a fake terminal is fairly easy.
-- See http://github.com/civboot/ele for an example.
M.Term = {
  w=-1, h=-1, l=-1, c=-1,
  golc = function(t, l, c) -- term:golc(l, c)
    M.golc(l, c); t.l, t.c = l, c
  end,
  -- TODO: remove golc here. Just write.
  set = function(t, l, c, char) -- term:set(l, c, 'f')
    t:golc(l, c); io.write(char)
    c = c + 1; t.c = (c<t.w) and c or t.w
  end,
  clear = function(t) -- term:clear()
    M.clear(); t.l, t.c = 1, 1
  end,
  -- TODO: remove the golc here. Just cleareol.
  cleareol = function(t, l, c)
    t:golc(l, c); M.cleareol()
  end,
  size = function(t) -- h, w = term:size()
    t.h, t.w = M.size(); return t.h, t.w
  end,
  start=M.enterRawMode,
  stop=M.exitRawMode,
}

return M

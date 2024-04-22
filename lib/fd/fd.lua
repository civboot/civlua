local pkg = require'pkg'
local sfmt = string.format
local NL = -string.byte'\n'

local S = pkg'fd.sys'
local M = {sync={}, async={}}

local MFLAGS = {
  ['r']  = S.O_RDONLY, ['r+']= S.O_RDWR,
  ['w']  = S.O_WRONLY | S.O_CREAT | S.O_TRUNC,
  ['a']  = S.O_WRONLY | S.O_CREAT | S.O_APPEND,
  ['w+'] = S.O_RDWR   | S.O_CREAT | S.O_TRUNC,
  ['a+'] = S.O_RDWR   | S.O_CREAT | S.O_APPEND,
}

local function waitReady(fd, poll)
  while fd:code() == S.FD_RUNNING do
    coroutine.yield(si.poll(fd:fileno(), poll))
  end
end

local YIELD_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
  [S.FD_RUNNING] = true,
}

M.sync.open = function(path, mode)
  local flags = assert(MFLAGS[mode:gsub('b', '')], 'invalid mode')
  local f = S.openFD(path, flags)
  if f:code() ~= 0 then
    error(sfmt("open failed: %s", f:codestr()))
  end
  return f
end
M.open = M.sync.open

----------------------------
-- WRITE
S.FD.__index.write = function(fd, str)
  waitReady(fd, S.POLLOUT);
  fd:_writepre(str)
  while true do
    local c = fd:_write()
    if YIELD_CODE[c] then
      coroutine.yield(si.poll(fd:fileno(), S.POLLOUT))
    elseif c ~= 0 then error(fd:codestr())
    else return end
  end
end

----------------------------
-- READ

-- perform a read, handling WOULDBLOCK.
-- return true if should be called again.
local function readYield(fd, till) --> done
  waitReady(fd, S.POLLIN);
  while true do
    local c = fd:_read(till)
    if YIELD_CODE[c] then
      coroutine.yield(si.poll(fd:fileno(), S.POLLIN))
    elseif c ~= 0 then error(fd:codestr())
    else return end
  end
end

-- Different read modes
local function iden(x) return x end
local function noNL(s)
  return s and (s:sub(-1) == '\n') and s:sub(1, -2) or s
end
local function readAll(fd) readYield(fd); return fd:_pop() end
local function readLine(fd, lineFn)
  local s = fd:_pop(NL); if s then return lineFn(s) end
  readYield(fd, NL)
  return lineFn(fd:_pop(NL) or fd:_pop())
end
local function readLineNoNL(fd)  return readLine(fd, noNL) end
local function readLineYesNL(fd) return readLine(fd, iden) end
local READ_MODE = {
  a=readAll, ['a*']=readAll, l=readLineNoNL, L=readLineYesNL,
}
local function readAmt(fd, amt)
  assert(amt > 0, 'read non-positive amount')
  local s = fd:_pop(amt); if s then return s end
  readYield(fd, amt)
  return lineFn(fd:_pop(amt) or fd:_pop())
end

S.FD.__index.read = function(fd, mode)
  if type(mode) == 'number' then return readAmt(fd, amt) end
  local fn = assert(READ_MODE[mode or 'a'], 'mode not supported')
  return fn(fd, mode)
end

----------------------------
-- SEEK
local WHENCE = { set=S.SEEK_SET, cur=S.SEEK_CUR, ['end']=S.SEEK_END }
S.FD.__index.seek = function(fd, whence, offset)
  local wh = assert(WHENCE[whence or 'cur'], 'unrecognized whence')
  return fd:_seek(offset or 0, wh)
end

return M

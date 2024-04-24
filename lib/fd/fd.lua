local sfmt      = string.format
local push, pop = table.insert, table.remove
local yield     = coroutine.yield
local NL        = -string.byte'\n'

local pkg = require'pkg'

local S = pkg'fd.sys'
local MFLAGS = {
  ['r']  = S.O_RDONLY, ['r+']= S.O_RDWR,
  ['w']  = S.O_WRONLY | S.O_CREAT | S.O_TRUNC,
  ['a']  = S.O_WRONLY | S.O_CREAT | S.O_APPEND,
  ['w+'] = S.O_RDWR   | S.O_CREAT | S.O_TRUNC,
  ['a+'] = S.O_RDWR   | S.O_CREAT | S.O_APPEND,
}
local YIELD_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
  [S.FD_RUNNING] = true,
}
local DONE_CODE = { [S.FD_EOF] = true, [0] = true }

local M = {
  sys = S,
  _sync={}, _async={}, _io = {},
     FD=S.FD,         FDT=S.FDT,
  newFD = S.newFD, newFDT=S.newFDT,
}

M.assertReady = function(fd, name)
  if fd:code() < S.FD_EOF then error(name..': fd not ready') end
end
M.finishYield = function(fd, kind, ...)
  while YIELD_CODE[fd:code()] do yield(kind or true, ...) end
end
M.finishRunning = function(fd, kind, ...)
  while fd:code() == S.FD_RUNNING do yield(kind or true, ...) end
end

----------------------------
-- WRITE / SEEK
S.FD.__index.write = function(fd, str)
  M.assertReady(fd, 'write')
  fd:_writepre(str)
  while true do
    local c = fd:_write()
    if YIELD_CODE[c] then
      coroutine.yield(si.poll(fd:fileno(), S.POLLOUT))
    elseif c ~= 0 then error(fd:codestr())
    else return end
  end
end

local WHENCE = { set=S.SEEK_SET, cur=S.SEEK_CUR, ['end']=S.SEEK_END }
S.FD.__index.seek = function(fd, whence, offset)
  M.assertReady(fd, 'seek')
  whence = assert(WHENCE[whence or 'cur'], 'unrecognized whence')
  return fd:_seek(offset or 0, whence)
end

S.FD.__index.flush = function(fd)
  M.assertReady(fd, 'flush')
  fd:_flush(); M.finishRunning(fd, 'sleep', 0.005)
  if not DONE_CODE[fd:code()] then error('flush: '..fd:codestr()) end
end

S.FD.__index.flags = function(fd)
  local code, flags = fd:_getflags()
  if code ~= 0 then error(fd:codestr()) end
  return flags
end
S.FD.__index.toNonblock = function(fd)
  M.assertReady(fd, 'toAsync')
  if fd:_setflags(S.O_NONBLOCK | fd:flags()) ~= 0 then
    error(fd:codestr())
  end
end
S.FD.__index.toBlock = function(fd)
  M.assertReady(fd, 'toSync')
  if fd:_setflags(S.inv(S.O_NONBLOCK) & fd:flags()) ~= 0 then
    error(fd:codestr())
  end
end
S.FD.__index.isAsync = function(fd)
  return (fd:flags() & S.O_NONBLOCK) ~= 0
end

----------------------------
-- READ

-- perform a read, handling WOULDBLOCK.
-- return true if should be called again.
local function readYield(fd, till) --> done
  fd:_read(till)
  while true do
    local c = fd:code()
    if c == 0        then c = fd:_read(till) end
    if DONE_CODE[c]  then return end
    if YIELD_CODE[c] then yield('poll', fd:fileno(), S.POLLIN)
    else                  error(fd:codestr()) end
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
  M.assertReady(fd, 'read')
  if type(mode) == 'number' then return readAmt(fd, amt) end
  local fn = assert(READ_MODE[mode or 'a'], 'mode not supported')
  return fn(fd, mode)
end

----------------------------
-- FDT
-- Note that FDT is IDENTICAL to FD except it's possible
-- that code() will be a FD_RUNNING. This is already handled,
-- as that is included as a YIELD_CODE (FD can be non-blocking)
S.FDT.__index.write      = S.FD.__index.write
S.FDT.__index.seek       = S.FD.__index.seek
S.FDT.__index.read       = S.FD.__index.read
S.FDT.__index.flush      = S.FD.__index.flush
S.FDT.__index.flags      = S.FD.__index.flags
S.FDT.__index.toNonblock = S.FD.__index.toNonblock
S.FDT.__index.toBlock    = S.FD.__index.toBlock
S.FDT.__index.isAsync    = function() return true end

S.FDT.__index.close = function(fd)
  fd:_close(); M.finishRunning(fd, 'sleep', 0.001)
end

----------------------------
-- PollList
M.PollList = setmetatable({
  __name='PollList',
}, {
  __call=function(ty_)
    return setmetatable({
      _pl=S.pollList(),
      map  = {}, -- map of fileno -> pl[index]
      avail = {}, -- list of available indexes
    }, ty_)
  end,
})
M.PollList.__len = function(pl) return pl._pl:size() - #pl.avail end
M.PollList.resize = function(pl, newSize)
  local size = pl._pl:size(); assert(newSize >= size, 'attempted shrink')
  pl._pl:resize(newSize); for i=size,newSize-1 do push(pl.avail, i) end
end
M.PollList.insert = function(pl, fileno, events)
  local i = pl.map[fileno] or pop(pl.avail)
  if not i then
    pl:resize((pl.size == 0) and 8 or pl.size * 2)
    i = assert(pop(pl.avail), 'failed to resize')
  end
  pl._pl:set(i, fileno, events)
  pl.map[fileno] = i
end

----------------------------
-- io backfill

M.openWith = function(openFn, path, mode)
  mode = mode or 'r'
  local flags = assert(MFLAGS[mode:gsub('b', '')], 'invalid mode')
  local f = openFn(path, flags); M.finishRunning(f, 'sleep', 0.005)
  if f:code() ~= 0 then error(sfmt("open failed: %s", f:codestr())) end
  return f
end
M.openFD  = function(...) return M.openWith(S.openFD, ...)  end
M.openFDT = function(...) return M.openWith(S.openFDT, ...) end
M.open = function(...)
  return M.openWith((LAP_ASYNC and S.openFDT) or S.openFD, ...)
end
M.close   = function(fd) fd:close() end
M.tmpfile = function(template, sysTmp)
  sysOpen = sysTmp or (LAP_ASYNC and S.tmpFDT) or S.tmpFD
  local f = sysTmp(template)
  M.finishRunning(f, 'sleep', 0.005)
  if f:code() ~= 0 then error(sfmt("tmp failed: %s", f:codestr())) end
end

M.read    = function(...) M.input():read(...) end
M.lines   = function(path, mode)
  if not path then return M.input():lines(mode) end
  local fd = M.open(path)
  local fn = function()
    if not fd then return end
    local l = fd:read(mode); if l then return l end
    fd:close(); fd = nil
  end
  return fn, nil, nil, fd
end
M.write = function(...) M.output():write(...) end

M.openFileno = function(fileno)
  local fd = S.newFD(); fd:_setfileno(fileno)
  return fd
end
M.stdin  = M.openFileno(S.STDIN_FILENO)
M.stdout = M.openFileno(S.STDOUT_FILENO)
M.stderr = M.openFileno(S.STDERR_FILENO)

M.input  = function() return M.stdin end
M.output = function() return M.stdout end
M.flush  = function() return M.output():flush() end

local FD_TYPES = {[S.FD] = true, [S.FDT] = true}

M.type   = function(fd)
  local mt = getmetatable(fd)
  if mt and FD_TYPES[mt] then
    return (fd:fileno() >= 0) and 'file' or 'closed file'
  end
  return M._io.type(fd)
end

----------------------------
-- To Sync / Async

local function toAsync()
  for k, v in pairs(M._async) do M[k] = v end
  for _, k in ipairs{'stdin', 'stdout', 'stderr'} do M[k]:toNonblock() end
end
local function toSync()
  for k, v in pairs(M._sync)  do M[k] = v end
  for _, k in ipairs{'stdin', 'stdout', 'stderr'} do M[k]:toBlock() end
end
if LAP_ASYNC then toAsync() else toSync() end

local IO_KEYS = [[
open     close   tmpfile
read     lines   write
stdout   stderr  stdin
input    output  flush
type
]]
local function copyKeys(keys, from, to)
  for k in keys:gmatch'%w+' do to[k] = from[k] end
  return cache
end
copyKeys(IO_KEYS, io, M._io)

M.ioAsync = function()
  assert(LAP_ASYNC, 'make async before calling ioAsync')
  copyKeys(IO_KEYS, M, io)
end


return M

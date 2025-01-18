local G = G or _G
--- filedescriptor: direct control of filedescriptors.
--- async operations support the LAP (see lib/lap) protocol.
---
--- Can override default `io` module for global async mode.
local M = mod and mod'fd' or {}

--- protocol globals (CIV and LAP protocols)
G.CWD = G.CWD or os.getenv'PWD' or os.getenv'CD' -- current working dir
G.LAP_FNS_ASYNC = G.LAP_FNS_ASYNC or {}
G.LAP_FNS_SYNC  = G.LAP_FNS_SYNC  or {}

local trace = G.LOG and G.LOG.trace or function() end
local S = require'fd.sys' -- fd.c, fd.h

local sfmt      = string.format
local push, pop = table.insert, table.remove
local yield     = coroutine.yield
local NL        = -string.byte'\n'
local iotype    = io.type

S.POLLIO = S.POLLIN | S.POLLOUT

M.FMODE = {
  [S.S_IFSOCK] = 'sock', [S.S_IFLNK] = 'link', [S.S_IFREG] = 'file',
  [S.S_IFBLK]  = 'blk',  [S.S_IFDIR] = 'dir',  [S.S_IFCHR] = 'chr',
  [S.S_IFIFO]  = 'fifo',
}

local MFLAGS = {
  ['r']  = S.O_RDONLY, ['r+']= S.O_RDWR,
  ['w']  = S.O_WRONLY | S.O_CREAT | S.O_TRUNC,
  ['a']  = S.O_WRONLY | S.O_CREAT | S.O_APPEND,
  ['w+'] = S.O_RDWR   | S.O_CREAT | S.O_TRUNC,
  ['a+'] = S.O_RDWR   | S.O_CREAT | S.O_APPEND,
}

local AGAIN_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
}
local YIELD_CODE = {
  [S.EWOULDBLOCK] = true, [S.EAGAIN] = true,
  [S.FD_RUNNING] = true,
}
local DONE_CODE = { [S.FD_EOF] = true, [0] = true }

M.sys = S
M._sync  = mod and mod'fd(sync)'  or {} -- sync functions
M._async = mod and mod'fd(async)' or {} -- async functions
M.io = {}  -- io cache

M.FD=S.FD;         M.FDT=S.FDT
M.newFD = S.newFD; M.newFDT=S.newFDT
M.PIPE_BUF = 512 -- POSIX.1

S.FD.__close  = S.FD.__index.close
S.FD.__name = 'fd.FD'
S.FD.__tostring = function(fd) return sfmt('FD(%s)', fd:fileno()) end
S.FDT.__close = S.FDT.__index.close
S.FDT.__name = 'fd.FDT'
S.FDT.__tostring = S.FD.__tostring

M.finishRunning = function(fd, kind, ...)
  while fd:code() == S.FD_RUNNING do yield(kind or true, ...) end
end

----------------------------
-- WRITE / SEEK

S.FD.__index.write = function(fd, ...)
  local s = table.concat{...}
  local c = fd:_write(s, 0)
  while YIELD_CODE[c] do
    yield('poll', fd:fileno(), S.POLLOUT)
    c = fd:_write(s)
  end
  if c > 0 then error(fd:codestr()) end
  return fd
end
M.FDT.__index.write = function(fd, ...)
  local s = table.concat{...}
  fd:_write(s)
  M.finishRunning(fd, 'poll', fd:_evfileno(), S.POLLIN)
  return fd
end

local WHENCE = { set=S.SEEK_SET, cur=S.SEEK_CUR, ['end']=S.SEEK_END }
S.FD.__index.seek = function(fd, whence, offset)
  whence = assert(WHENCE[whence or 'cur'], 'unrecognized whence')
  fd:_seek(offset or 0, whence)
  M.finishRunning(fd, 'poll', fd:getpoll(S.POLLIN | S.POLLOUT))
  if(fd:code() > 0) then error(fd:codestr()) end
  return fd:pos()
end

S.FD.__index.flush = function(fd)
  fd:_flush(); M.finishRunning(fd, 'sleep', 0.001)
  if fd:code() ~= 0 then error('flush: '..fd:codestr()) end
end

S.FD.__index.flags = function(fd)
  local code, flags = fd:_getflags()
  if code ~= 0 then error(fd:codestr()) end
  return flags
end
S.FD.__index.toNonblock = function(fd)
  if fd:_setflags(S.O_NONBLOCK | fd:flags()) ~= 0 then
    error(fd:codestr())
  end; return fd
end
S.FD.__index.toBlock = function(fd)
  if fd:_setflags(~S.O_NONBLOCK & fd:flags()) ~= 0 then
    error(fd:codestr())
  end; return fd
end
S.FD.__index.isAsync = function(fd)
  return (fd:flags() & S.O_NONBLOCK) ~= 0
end

S.FD.__index.getpoll = function(fd, events)
  return fd:fileno(), events
end
S.FDT.__index.getpoll = function(fdt)
  return fdt:_evfileno(), S.POLLIN
end

----------------------------
-- READ

--- FD's read may need to be called multiple times (O_NONBLOCK)
--- FDT's read CANNOT be called multiple times.
local function readLap(fd, c)
  if DONE_CODE[c]    then return end
  if YIELD_CODE[c]   then
    yield('poll', fd:getpoll(S.POLLIN))
    return true
  end
  error(sfmt('%s (%s)', fd:codestr(), c))
end
S.FD.__index._readTill = function(fd, till)
  while readLap(fd, fd:_read(till)) do end
end
S.FDT.__index._readTill = function(fd, till)
  fd:_read(till)
  while readLap(fd, fd:code()) do end
end

--- Different read modes
local function iden(x) return x end
local function noNL(s)
  return s and (s:sub(-1) == '\n') and s:sub(1, -2) or s
end
local function readAll(fd) fd:_readTill(); return fd:_pop() or '' end
local function readLine(fd, lineFn)
  local s = fd:_pop(NL); if s then return lineFn(s) end
  fd:_readTill(NL)
  local out = lineFn(fd:_pop(NL) or fd:_pop())
  return out
end
local function readLineNoNL(fd)  return readLine(fd, noNL) end
local function readLineYesNL(fd) return readLine(fd, iden) end
local function readAmt(fd, amt)
  assert(amt > 0, 'read non-positive amount')
  local s = fd:_pop(amt); if s then return s end
  fd:_readTill(amt)
  return fd:_pop(amt) or fd:_pop()
end

local READ_MODE = {
  a=readAll, ['*a']=readAll, l=readLineNoNL, L=readLineYesNL,
}
local modeFn = function(mode)
  local fn = (type(mode) == 'number') and readAmt or READ_MODE[mode or 'a']
  if not fn then error('mode not supported: '..tostring(mode)) end
  return fn
end
S.FD.__index.read = function(fd, mode)
  return modeFn(mode)(fd, mode)
end

S.FD.__index.lines = function(fd, mode)
  local fn = modeFn(mode or 'l')
  return function() return fn(fd, mode) end
end

----------------------------
-- FDT
--- Note that FDT is IDENTICAL to FD except it's possible
--- that code() will be a FD_RUNNING. This is already handled,
--- as that is included as a YIELD_CODE (FD can be non-blocking)
S.FDT.__index.seek       = S.FD.__index.seek
S.FDT.__index.read       = S.FD.__index.read
S.FDT.__index.lines      = S.FD.__index.lines
S.FDT.__index.flush      = S.FD.__index.flush
S.FDT.__index.flags      = S.FD.__index.flags
S.FDT.__index.toNonblock = function() error'invalid' end
S.FDT.__index.toBlock    = function() error'invalid' end
S.FDT.__index.isAsync    = function() return true end

S.FDT.__index.close = function(fd)
  M.finishRunning(fd, 'sleep', 0.001)
  fd:_close();
end

----------------------------
-- PollList
M.PollList = setmetatable({
__name='PollList',
__index = {
  __len = function(pl) return pl._pl:size() - #pl.avail end,
  resize = function(pl, newSize)
    local size = pl._pl:size(); assert(newSize >= size, 'attempted shrink')
    pl._pl:resize(newSize); for i=size,newSize-1 do push(pl.avail, i) end
  end,
  insert = function(pl, fileno, events)
    local i = pl.map[fileno] or pop(pl.avail)
    if not i then
      pl:resize((pl._pl:size() == 0) and 8 or pl._pl.size() * 2)
      i = assert(pop(pl.avail), 'failed to resize')
    end
    pl._pl:set(i, fileno, events)
    pl.map[fileno] = i
  end,
  ready = function(pl, timeoutSec)
    return pl._pl:ready(math.floor(timeoutSec * 1000))
  end,
  remove = function(pl, fileno)
    local i = assert(pl.map[fileno])
    push(pl.avail, i); pl.map[fileno] = nil;
    pl._pl:set(i, -1, 0)
  end,
}}, {
  __call=function(ty_)
    return setmetatable({
      _pl=S.pollList(),
      map  = {}, -- map of fileno -> pl[index]
      avail = {}, -- list of available indexes
    }, ty_)
  end,
})

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
M.tmpfileFn = function(sysFn)
  local f = sysFn(); M.finishRunning(f, 'sleep', 0.005)
  if f:code() ~= 0 then error(sfmt("tmp failed: %s", f:codestr())) end
  return f
end
M._sync.tmpfile  = function() return M.tmpfileFn(S.tmpFD)  end
M._async.tmpfile = function() return M.tmpfileFn(S.tmpFDT) end

M.read    = function(...)
  local inp = M.input()
  io.stderr:flush()
  return inp:read(...)
end
M.lines   = function(path, mode)
  mode = mode or 'l'
  if not path then return M.input():lines(mode) end
  local fd = M.open(path)
  local fn = function()
    if not fd then return end
    local l = fd:read(mode)
    if l then return l end
    fd:close(); fd = nil
  end
  return fn, nil, nil, fd
end
M.write = function(...) return M.output():write(...) end

M.openFileno = function(fileno)
  local fd = S.newFD(); fd:_setfileno(fileno)
  return fd
end
M.stdin  = M.openFileno(S.STDIN_FILENO)
M.stdout = M.openFileno(S.STDOUT_FILENO)

M.input  = function() return M.stdin end
M.output = function() return M.stdout end
M.flush  = function() return M.output():flush() end

local FD_TYPES = {[S.FD] = true, [S.FDT] = true}

M.type   = function(fd)
  local mt = getmetatable(fd)
  if mt and FD_TYPES[mt] then
    return (fd:fileno() >= 0) and 'file' or 'closed file'
  end
  return iotype(fd)
end
M.fileno = function(fd)
  if iotype(fd) then return S.fileno(fd) end
  if type(fd) == 'userdata' then return fd:fileno() end
  local meth = rawget(getmetatable(fd), 'fileno')
  return meth and meth(fd)
end
M.ftype = function(f)
  local t = M.FMODE[S.S_IFMT & S.fstmode(M.fileno(f))]
  if t then return t end
  return nil, 'file has unknown mode'
end
M.isatty = function(fd)
  fd = type(fd) == 'number' and fd or M.fileno(fd)
  return fd and S.isatty(fd)
end

----------------------------
-- To Sync / Async

push(LAP_FNS_ASYNC, function()
  for k, v in pairs(M._async) do M[k] = v end
end)
push(LAP_FNS_SYNC, function()
  for k, v in pairs(M._sync)  do M[k] = v end
end)

local IO_KEYS = [[
open   close  tmpfile
read   lines  write
stdout stdin
input  output flush
type
]]
local function copyKeysM(keys, from, to)
  for k in keys:gmatch'%w+' do
    to[k] = assert(rawget(from, k) or M[k])
  end
end
copyKeysM(IO_KEYS, io, M.io)

M.ioSync = function()
  assert(not LAP_ASYNC); copyKeysM(IO_KEYS, M._sync, io)
end
M.ioAsync = function()
  assert(LAP_ASYNC);     copyKeysM(IO_KEYS, M._async, io)
end

return M

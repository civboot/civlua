local sfmt      = string.format
local push, pop = table.insert, table.remove
local yield     = coroutine.yield
local NL        = -string.byte'\n'


local S = require'fd.sys'
S.POLLIO = S.POLLIN | S.POLLOUT

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

local M = {
  sys = S,
  _sync={}, _async={}, _io = {},
     FD=S.FD,         FDT=S.FDT,
  newFD = S.newFD, newFDT=S.newFDT,
}

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
end
M.FDT.__index.write = function(fd, ...)
  local s = table.concat{...}
  fd:_write(s)
  M.finishRunning(fd, 'poll', fd:_evfileno(), S.POLLOUT)
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
  if fd:_setflags(S.inv(S.O_NONBLOCK) & fd:flags()) ~= 0 then
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
  return fdt:_evfileno(), S.POLLOUT
end

----------------------------
-- READ

-- FD's read may need to be called multiple times (O_NONBLOCK)
-- FDT's read CANNOT be called multiple times.
local function readLap(fd, c)
  if DONE_CODE[c]    then return end
  if YIELD_CODE[c]   then yield('poll', fd:getpoll(S.POLLIN))
  else               error(sfmt('%s (%s)', fd:codestr(), c)) end
  return true
end
S.FD.__index._readTill = function(fd, till)
  while readLap(fd, fd:_read(till)) do end
end
S.FDT.__index._readTill = function(fd, till)
  fd:_read(till)
  while readLap(fd, fd:code()) do end
end

-- Different read modes
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
  local out = modeFn(mode)(fd, mode)
  return out
end

S.FD.__index.lines = function(fd, mode)
  local fn = modeFn(mode or 'l')
  return function() return fn(fd, mode) end
end

S.FD.__bor = function(fd, w) -- fd | Sh'some command'
  for l in fd:lines'L' do w:write(l) end
  return w
end

S.FD.__shr = function(fd, path) -- fd >> '/tmp/example.txt'
  local w = S.open(path, 'w')
  for bl in fd:lines(S.IO_SIZE) do w:write(bl) end
  w:close()
  return fd
end

----------------------------
-- FDT
-- Note that FDT is IDENTICAL to FD except it's possible
-- that code() will be a FD_RUNNING. This is already handled,
-- as that is included as a YIELD_CODE (FD can be non-blocking)
S.FDT.__index.seek       = S.FD.__index.seek
S.FDT.__index.read       = S.FD.__index.read
S.FDT.__index.lines      = S.FD.__index.lines
S.FDT.__index.flush      = S.FD.__index.flush
S.FDT.__index.flags      = S.FD.__index.flags
S.FDT.__index.toNonblock = function() error'invalid' end
S.FDT.__index.toBlock    = function() error'invalid' end
S.FDT.__index.isAsync    = function() return true end

S.FDT.__bor = S.FD.__bor; S.FDT.__shr = S.FD.__shr

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
  local f = sysFn(template or ''); M.finishRunning(f, 'sleep', 0.005)
  if f:code() ~= 0 then error(sfmt("tmp failed: %s", f:codestr())) end
  return f
end
M._sync.tmpfile  = function() return M.tmpfileFn(S.tmpFD)  end
M._async.tmpfile = function() return M.tmpfileFn(S.tmpFDT) end

M.read    = function(...) M.input():read(...) end
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
open   close  tmpfile
read   lines  write
stdout stderr stdin
input  output flush
type
]]
local function copyKeys(keys, from, to)
  for k in keys:gmatch'%w+' do to[k] = from[k] end
  return cache
end
copyKeys(IO_KEYS, io, M._io)

M.ioAsync = function()
  assert(LAP_ASYNC);     copyKeys(IO_KEYS, M, io)
end
M.ioSync = function()
  assert(not LAP_ASYNC); copyKeys(IO_KEYS, M, io)
end

return M

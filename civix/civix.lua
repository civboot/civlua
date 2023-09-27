local mty = require'metaty'
local ds = require'ds'
local posix = require'posix'

local M = {
  std_r = 0, std_w = 1, std_lw = 2,
  PIPE_R = io.stdin,
  PIPE_W = io.stdout,
  PIPE_LW = io.stderr,
}

assert(M.std_r  == posix.fileno(io.stdin))
assert(M.std_w  == posix.fileno(io.stdout))
assert(M.std_lw == posix.fileno(io.stderr))

local function sleep(duration)
  posix.nanosleep(duration.s, duration.ns)
end

-- Return the epoch time
local function epoch()
  local s, ns, errnum = posix.clock_gettime(posix.CLOCK_REALTIME)
  assert(s); assert(ns)
  return ds.Epoch(s, ns)
end

M.Pipe = mty.record'Pipe'
  :field('fd', 'number')
  :field('closed', 'boolean', false)

M.Pipe.close = function(self)
  if not self.closed then
    posix.close(self.fd); self.closed = true
  end
end

M.Pipe.read = function(self, m)
  local i = 1
  if('a' == m or 'a*' == m) then
    local t = {};
    while true do
      i = i + 1
      local s, err = posix.read(self.fd, 1024)
      if nil == s then return nil, err end
      table.insert(t, s)
      if '' == s then return table.concat(t) end
    end
  end
  return posix.read(self.fd, 1024)
end
M.Pipe.write = function(self, w) return posix.write(self.fd, w) end

local function pipe()
  local r, w = posix.pipe()
  assert(r, 'no read'); assert(w, 'no write')
  return r, w
end

-- Standard pipes for a process:
-- * r = read from pipe  (stdout)
-- * w = write to pipe   (stdin)
-- * lw = log write pipe (stderr)
-- * lr = log read pipe  (parent reading child stderr)
M.Pipes = mty.record'Pipes'
  :fieldMaybe'r'  :fieldMaybe'w'
  :fieldMaybe'lr' :fieldMaybe'lw'

-- Pipes:from constructor from existing filedescriptors
-- of form `{r=fd, w=fd, lr=fd, lw=fd}`
M.Pipes.from = function(ty_, fds)
  local p = M.Pipes{}; for k, fd in pairs(fds) do p[k] = M.Pipe{fd=fd} end
  return p
end

-- close all the pipes (in parent or child)
M.Pipes.close = function(p)
  if p.r  then p.r:close()  ; p.r  = nil end
  if p.w  then p.w:close()  ; p.w  = nil end
  if p.lr then p.lr:close() ; p.lr = nil end
  if p.lw then p.lw:close() ; p.lw = nil end
end

M.Pipes.dupStd = function(p)
  -- dup pipes to std file descriptors
  if p.r  then posix.dup2(p.r.fd,  M.std_r) end
  if p.w  then posix.dup2(p.w.fd,  M.std_w) end
  if p.lw then posix.dup2(p.lw.fd, M.std_lw) end
end

-- Fork the current process (see constructor)
M.Fork = mty.record'Fork'
  :field('status', 'string', 'running')
  :fieldMaybe('isParent', 'boolean')
  :fieldMaybe('pipes', M.Pipes)
  :fieldMaybe('rc', 'number')

-- Fork constructor:
-- r=true creates parent.r and child.w   (parent reads child's stdout)
-- w=true creates parent.w and child.r   (parent writes to child's stdin)
-- l=true creates parent.rl and child.wl (parent reads to child's stderr)
M.Fork:new(function(ty_, r, w, l)
  local parent, child = {}, {}
  if r then parent.r , child.w  = pipe() end
  if w then child.r,   parent.w = pipe() end
  if l then parent.lr, child.lw = pipe() end
  parent, child = M.Pipes:from(parent), M.Pipes:from(child)
  local self = {cpid = posix.fork()}
  if(not self.cpid) then error('fork failed') end
  if 0 == self.cpid then -- is child
    parent:close() -- parent's side of pipes are not used in child fork
    self.pipes = child
    child:dupStd() -- stdin/out/err needs to be updated for child
  else
    child:close()
    self.pipes = parent
    self.isParent = true
  end
  return setmetatable(self, ty_)
end)

-- call posix.wait and return isDone, err, errNum
M.Fork.wait = function(self)
  assert(self.isParent, 'wait() can only be called on parent')
  mty.assertf(self.status == 'running',
              "wait called when not running, status=%s", self.status)
  self.pipes:close()
  local a, b, c = posix.wait(self.cpid)
  if nil == a then self.status = 'error'; return nil, b, c end
  if 'running' == b then return false end
  self.rc = c; self.status = b; return true
end

-- Execute a shell command on the child. This terminates
-- the child process (since exec doesn't typically return).
M.Fork.exec = function(self, cmd)
  assert(not self.isParent, 'exec can only be called on child')
  local a, err = posix.exec('/bin/sh', {'-c', cmd, nil}) -- TODO: remove nil?
  if nil == a then error(err) end
  os.exit(0)
end

return M

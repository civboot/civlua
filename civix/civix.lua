local mty = require'metaty'
local ds = require'ds'
local posix = require'posix'

local add, concat = table.insert, table.concat
local function asStr(v)
  if 'table' == type(v) then        return concat(v)
  elseif 'userdata' == type(v) then return v:read('*a') end
  return v
end

local M = {
  std_r = 0, std_w = 1, std_lw = 2,
  PIPE_R = io.stdin,
  PIPE_W = io.stdout,
  PIPE_LW = io.stderr,
}

-- "global" shell settings
M.SH_SET = { debug=false, host=false }

assert(M.std_r  == posix.fileno(io.stdin))
assert(M.std_w  == posix.fileno(io.stdout))
assert(M.std_lw == posix.fileno(io.stderr))

-------------------------------------
-- Time Functions

-- Sleep for a duration
M.sleep = function(duration)
  posix.nanosleep(duration.s, duration.ns)
end

-- Return the Epoch time
M.epoch = function()
  local s, ns, errnum = posix.clock_gettime(posix.CLOCK_REALTIME)
  assert(s); assert(ns)
  return ds.Epoch(s, ns)
end

-------------------------------------
-- Pipe

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

-------------------------------------
-- Fork(r, w, l): fork the current process with pipes attached
--
-- Args:
--   r=true creates parent.r and child.w   (parent reads child's stdout)
--   w=true creates parent.w and child.r   (parent writes to child's stdin)
--   l=true creates parent.rl and child.wl (parent reads to child's stderr)
M.Fork = mty.record'Fork'
  :field('status', 'string', 'running')
  :fieldMaybe('isParent', 'boolean')
  :fieldMaybe('pipes', M.Pipes)
  :fieldMaybe('rc', 'number')
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

-------------------------------------
-- sh(cmd, set): run a shell command
--
-- Args:
--   cmd: string or table. Will auto convert {key=value} to --key=value.
--   set: control over passed input, no/fork (with w/lr pipes), etc.
--        See ShSet.
--
-- Returns: ShResult

M.ShSet = mty.record'ShSet'
  :field('check', 'boolean', true) -- check the rc
  :field('inp',   'string',  false) -- value to send to process input
  :field('err',   'boolean', false) -- get stderr
  :field('debug', 'boolean', false) -- log all inputs/outputs
  :fieldMaybe('log', mty.Any)       -- log/stderr pipe

  -- return out.fork. Don't get the output or stop the fork.
  :field('fork',  'boolean', false)

  -- requires fork=true. Will cause fork to have a pipe with
  -- the corresponding field/s
  :fieldMaybe'w'  -- create/use a write pipe
  :fieldMaybe'lr' -- create/use a log-read (stderr) pipe

  -- Used for xsh
  :fieldMaybe('host', 'string')

M.ShResult = mty.record'ShResult'
  :field('status', Str) -- the status of the fork

  -- These are only available when fork=false
  :fieldMaybe('rc',  Num) -- the return code
  :fieldMaybe('out', Str) -- the output
  :fieldMaybe('err', Str) -- the stderr

  -- These can only be available when fork=true
  -- Note: fork.pipes will have the requested {r, w, lr}
  :fieldMaybe('fork', M.Fork)

M.quote = function(v)
  v = asStr(v)
  if string.match(v, "'") then return nil end -- cannot quote values with '
  return "'" .. v .. "'"
end

-- execute a command, using lua's shell
-- return {output, closeValues}
M.luash = function(c)
  local f = assert(io.popen(asStr(c)), 'r')
  return f:read('*a'), {f:close()}
end

-- Just get the command, don't do anything
--
-- returns cmdSettings, cmdBuf
M.shCmd = function(cmd, set)
  set = M.ShSet(set or {})
  if nil == set.debug then set.debug = M.SH_SET.debug end
  if nil == set.check and not set.fork then set.check = true end
  if set.check then assert(not set.fork) end
  if 'string' == type(cmd) then cmd = {cmd}
  else                          cmd = ds.copy(cmd) end
  assert(not (set.fork and set.err), "cannot set fork and err")

  for k, v in pairs(cmd) do
    if 'string' == type(k) then
      if type(v) == 'boolean' then
        add(cmd, concat({'--', k}))
      else
        v = M.quote(v); if not v then
          return nil, nil, 'flag "'..k..'" has single quote character'
        end
        add(cmd, concat({'--', k, '=', v}))
      end
    end
  end
  cmd = concat(cmd, ' ')
  assert(cmd:find'%S', 'cannot execute an empty command')
  return cmd, set
end

local function _sh(cmd, set, err)
  if err then error(err) end
  local log = set.log -- output
  if set.debug then
    log = log or io.stderr
    log:write('[==[ ', cmd, ' ]==]\n')
  end

  local res = M.ShResult{status='not-started'}
  local f = M.Fork(true, set.w or set.inp, set.lr or set.err)
  if not f.isParent then f:exec(cmd) --[[exits]] end
  res.status = 'started'
  if set.inp then
    -- write+close input so process can function
    f.pipes.w:write(set.inp)
    f.pipes.w:close(); f.pipes.w = nil
  end
  if set.fork then res.fork = f -- return fork to caller
  else                          -- else finish and close
    res.out = f.pipes.r:read('a')
    if set.err then res.err = f.pipes.lr:read('a') end
    while not f:wait() do M.sleep(0.05) end
    res.rc = f.rc
  end
  res.status = f.status
  if log and res.out then log:write(res.out, '\n') end
  if set.check and res.rc ~= 0 then error(
    'non-zero return code: ' .. tostring(res.rc)
  )end
  return res
end

-- Run a command on the unix shell with settings of ShSet.
M.sh = function(cmd, set)
  local cmd, set, err = M.shCmd(cmd, set);
  return _sh(cmd, set, err)
end

-- "user" variants that write to stdout
M.shu = function(cmd, set) io.stdout:write(M.sh(cmd, set)) end

return M

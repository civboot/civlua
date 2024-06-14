-- civix: unix-like OS utilities.
local M = mod and mod'civix' or {}

local mty  = require'metaty'
local ds   = require'ds'
local shim = require'shim'
local lib  = require'civix.lib'; local C = lib
local fd   = require'fd'
local lap  = require'lap'

local path = ds.path
local concat, sfmt = table.concat, string.format
local push, pop = table.insert, table.remove
local yield = coroutine.yield
local pc = path.concat

-- TODO: actually implement
lib.getpagesize = function() return 4096 end

ds.update(M, {
	-- file types
	SOCK = "sock", LINK = "link",
	FILE = "file", BLK  = "blk",
	DIR  = "dir",  CHR  = "chr",
	FIFO = "fifo",

	dir = lib.dir, rm=lib.rm, rmdir = lib.rmdir,
  exists = lib.exists,

  -- TODO: probably good to catch return code for cross-filesystem
  mv = lib.rename,
})

-------------------------------------
-- Utility

-- quote the str if it's possible
M.quote = function(str)
  if string.find(str, "'") then return nil end
  return "'" .. str .. "'"
end

-- "global" shell settings
M.SH_SET = { debug=false, host=false }

-------------------------------------
-- Time Functions
-- Sleep for the specified duration.
--   sleep(duration)
-- 
-- time can be a Duration or float (seconds).
-- A negative duration results in a noop.
M.sleep = function(d)
  if type(d) == 'number' then d = ds.Duration:fromSeconds(d) end
  if d.s >= 0 then lib.nanosleep(d.s, d.ns) end
end

-- Return the Epoch/Mono time
-- Time according to realtime clock
M.epoch   = function() return ds.Epoch(lib.epoch())   end
-- Duration according to monotomically incrementing clock.
M.mono    = function() return ds.Duration(lib.mono()) end
M.monoSec = function() return M.mono():asSeconds()    end

-------------------------------------
-- Core Filesystem

local function qp(p)
  return mty.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

M.fileno = function(f)
  local fno = f.fileno
  if fno then return (type(fno) == 'number') and fno or fno(f) end
  return lib.fileno(f)
end

M.MODE_STR = {
  [C.S_IFSOCK] = 'sock', [C.S_IFLNK] = 'link', [C.S_IFREG] = 'file',
  [C.S_IFBLK]  = 'blk',  [C.S_IFDIR] = 'dir',  [C.S_IFCHR] = 'chr',
  [C.S_IFIFO]  = 'fifo',
}
M.ftype = function(f)
  return assert(M.MODE_STR[C.S_IFMT & lib.fstmode(M.fileno(f))])
end

M.pathtype = function(path)
  return assert(M.MODE_STR[C.S_IFMT & lib.stmode(path)])
end

local function _walkcall(ftypeFns, path, ftype)
  local fn = ftypeFns[ftype] or ftypeFns.default
  if fn then return fn(path, ftype) end
end

local function _walk(base, ftypeFns, maxDepth, depth)
  if maxDepth and depth >= maxDepth then return end
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then ftype = M.pathtype(path) end
    local o = _walkcall(ftypeFns, path, ftype)
    if o == true then return end
    if o ~= 'skip' and ftype == 'dir' then
      _walk(path, ftypeFns, maxDepth, depth + 1)
    end
 	end
  if ftypeFns.dirDone then ftypeFns.dirDone(base, ftype) end
end


-- walk the paths up to depth, calling ftypeFns[ftype] for
-- each item encountered.
--
-- If depth is nil/false then the depth is infinite.
--
-- ftypeFns has two special keys:
--  * default: called if the ftype is not present
--  * dirDone: called AFTER the directory has been walked
--
-- The Fn signatures are: (path, depth) -> stopWalk
-- If either return true then the walk is ended immediately
-- If dirFn returns 'skip' then the directory is skipped
M.walk = function(paths, ftypeFns, maxDepth)
  for _, path in ipairs(paths) do
    assert('' ~= path, 'empty path')
    local ftype = M.pathtype(path); _walkcall(ftypeFns, path, ftype)
    if ftype == 'dir' then _walk(path, ftypeFns, maxDepth, 0) end
  end
end

-- A very simple ls (list paths) implementation
-- Returns (files, dirs) tables. Anything that is not a directory
-- is treated as a file.
M.ls = function(paths, maxDepth)
  local files, dirs = {}, {}
  M.walk(paths, {
    dir     = function(p) push(dirs,  pc{p, '/'}) end,
    default = function(p) push(files, p)          end,
  }, maxDepth or 1)
  return files, dirs
end

local RMR_FNS = {dir = ds.noop, default = M.rm, dirDone = M.rmdir }
M.rmRecursive = function(path)
  M.walk({path}, RMR_FNS, nil)
end
M.mkDirs = function(pthArr)
  local dir = ''; for _, c in ipairs(pthArr) do
    dir = pc{dir, c}
    local ok, errno = lib.mkdir(dir)
    if ok or (errno == C.EEXIST) then -- directory created or exists
    else mty.errorf('failed to create directory: %s (%s)', 
                    dir, lib.strerrno(errno)) end
  end
end
M.mkDir = function(pth, parents)
  if parents then M.mkDirs(path.splitList(pth))
  else mty.assertf(lib.mkdir(pth), "mkdir failed: %s", pth) end
end

-- mkTree(tree) builds a tree of files and dirs at `dir`.
-- Dirs  are tables.
-- Files are string or fd -- which are read+closed.
-- 
-- tree = {
--   a = {
--     ['a1.txt'] = 'stuff in a1.txt',
--     ['a2.txt'] = 'stuff in a.txt',
--     a3 = {
--       ['a4.txt'] = io.open'some/file.txt',
--     }
--   }
-- }
-- 
-- Builds a tree like
-- a/a1.txt    # content: stuff in a1.txt
-- a/a2.txt    # content: stuff in a2.txt
-- a/a3/a4.txt # content: stuff in a3.txt
M.mkTree = function(dir, tree, parents)
  M.mkDir(dir, parents)
  for name, v in pairs(tree) do
    local p = path.concat{dir, name, type(v) == 'table' and '/' or nil}
    if     type(v) == 'table'  then M.mkTree(p, v)
    elseif type(v) == 'string' then ds.writePath(p, v)
    elseif type(v) == 'userdata' then
      local f = ds.fdMv(io.popen(p, 'w'), v)
      f:close(); v:close()
    else error('invalid tree value of type '..type(v)) end
  end
end

M.Lap = function() return lap.Lap {
  sleepFn=M.sleep, monoFn=M.monoSec, pollList=fd.PollList(),
}end

-- Start args on the shell
-- Suggestion: use civix.sh instead.
--
-- Sh:start() kicks off a subprocess which start the shell using the fds you pass
-- in or creating them if you set them to true. Created file descriptors will be
-- stored in the associated name.
--
-- Why? This means that :close() will only close filedescriptors created by the
--      shell itself, and you won't accidentially close io.stdout/etc.
--
-- Examples (see civix.sh for more examples):
--   Lua                                              Bash
--   Sh({'ls', 'foo/bar'}, {stdout=io.stdout}):start()      -- ls foo/bar
--   v = Sh{'ls foo/bar', stdout=true}:start():read() -- v=$(ls foo/bar)
M.Sh = mty'Sh' {
  "args [table]: arguments to pass to shell",
  "stdin  [file|bool]: shell's stdin to send  (default=empty)",
  "stdout [file|bool]: shell's stdout              (default=empty)",
  "stderr [file|bool]: shell's stderr              (default=empty)",
  "env [list]:  shell's environment {'FOO=bar', ...}",
  '_sh [userdata]: internal C implemented shell',
}
getmetatable(M.Sh).__index = function(sh, k)
  local shv = rawget(sh, '_sh', k)
  if shv then return shv end
  if rawget(sh, '__fields')[k] then return nil end
  error('unknown field: '..k)
end

local function _fnomaybe(f, default)
  if type(f) == 'boolean' then return f end
  return f and M.fileno(f) or default
end
-- start the shell in the background.
-- sh{arg1, arg2, stdin=nostdin, stdout=true, stderr=io.stderr}
-- See Sh for how filedescriptors are set.
M.Sh.start = function(sh)
  local r, w, l = fd.newFD(), fd.newFD(), fd.newFD()
  local ex, _r, _w, _l = lib.sh(
    sh.args[1], sh.args, sh.env,
    _fnomaybe(sh.stdin), _fnomaybe(sh.stdout, true),
    _fnomaybe(sh.stderr, fd.sys.STDERR_FILENO)
  )
  sh._sh = ex
  if _r then r:_setfileno(_r); r:toNonblock() else r = nil end
  if _w then w:_setfileno(_w); w:toNonblock() else w = nil end
  if _l then l:_setfileno(_l); l:toNonblock() else l = nil end
  sh.stdin, sh.stdout, sh.stderr = w, r, l
  return sh
end

M.Sh.isDone = function(sh) return sh._sh:isDone() end

-- wait for shell to complete, returns return code
M.Sh.wait = function(sh)
  if LAP_ASYNC then
    while not sh:isDone() do yield('sleep', 0.005) end
  else sh._sh:wait() end
  return sh._sh:rc()
end

M.ShFin = mty'ShFin'{
  'stdin [file]', 'stdout [file]', 'stderr [file]',
  "input [string]: write to then close stdin (either self's or shell's)",
}
-- sh:finish{ShFin} -> out, err
-- finish files (in sh or other) by writing other.input to stdin and reading
-- stdout/stderr.  All processes are done asynchronously
M.Sh.finish = function(sh, other)
  other = M.ShFin(other or {})
  local inpf = other.stdin  or sh.stdin
  local outf = other.stdout or sh.stdout
  local errf = other.stderr or sh.stderr
  if not (other.input or outf or errf) then return end
  local fns, out, err = {}
  if other.input then assert(inpf, 'provided input without stdin')
    push(fns, function()
      inpf:write(other.input); inpf:close()
    end)
  end
  if outf then push(fns, function() out = outf:read() end) end
  if errf then push(fns, function() err = errf:read() end) end
  if LAP_ASYNC then lap.all(fns) else M.Lap():run(fns) end
  return out, err
end
M.Sh.write = function(sh, ...) return sh.stdin:write(...) end
M.Sh.read  = function(sh, ...) return sh.stdout:read(...) end

M._sh = function(cmd) --> Sh
  local pk, sh, other = ds.popk, {}, {}
  if type(cmd) == 'string' then cmd = shim.parseStr(cmd)
  else
    sh.stdin  = pk(cmd, 'stdin')
    sh.stdout = pk(cmd, 'stdout')
    sh.stderr = pk(cmd, 'stderr')
  end
  sh.args = shim.expand(cmd)
  if type(sh.stdin) == 'string' then
    if #sh.stdin > fd.PIPE_BUF then -- may block, use tmpfile
      local t = fd.tmpfile(); t:write(sh.stdin); t:seek'set'
      sh.stdin = t
    else other.input = sh.stdin; sh.stdin = true end
  end
  return M.Sh(sh), other
end

-- sh(cmd) -> out, err, sh
-- Execute the command in another process via execvp (system shell). Throws an
-- error if the command fails.
--
-- if cmd is a table, the following keys are treated as special. If you need any
-- of these then you must use M.Sh directly (recommendation: use Plumb)
--
--   stdin[string|file]: the process's stdin. If string it will be sent to stdin.
--   stdout[file]: the process's stdout. out will be nil if this is set
--   stderr[file]: the process's stderr (default=io.stderr)
--
-- Note: use Plumb{...}:run() if you want to pipe multiple shells together.
--
-- COMMAND                               BASH
-- sh'ls foo/bar'                     -- ls foo/bar
-- sh{'ls', 'foo/bar', 'dir w spc/'}  -- ls foo/bar "dir w spc/"
-- sh{stdin='sent to stdin', 'cat'}     -- echo "sent to stdin" | cat
M.sh = function(cmd)
  local sh, other = M._sh(cmd); sh:start()
  local out, err = sh:finish(other)
  local rc = sh:wait(); if rc ~= 0 then
    mty.errorf('Command failed with rc=%s: %q%s', rc, cmd,
      (out and (#out > 0) and ('\nSTDOUT:\n'..out) or ''))
  end
  return out, err, sh
end

return M

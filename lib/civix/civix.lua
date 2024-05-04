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
M.epoch =(
  function() return ds.Epoch(lib.epoch())   end)
-- Duration according to monotomically incrementing clock.
M.mono  =(
  function() return ds.Duration(lib.mono()) end)
M.monoSec = function() return M.mono():asSeconds() end

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

-- Sh: start args on the shell
-- Constructor: Sh(args, fds) -> Sh
--
-- Sh:start() kicks off a subprocess which start the shell using the fds you pass
-- in.
--
-- 1. If you didn't pass in inp/out then Sh:write()/Sh:read() will go to the
--    process's new stdin/stdout pipes.
-- 2. If you did pass in inp/out then those fields are set to nil. You can
--    write/read from an external reference.
--
-- Why? This means that :close() will only close filedescriptors created by the
--      shell itself, and you won't accidentially close io.stdout/etc.
--
-- Examples (see civix.sh for more examples):
--   Lua                                              Bash
--   Sh({'ls', 'foo/bar'}, {out=io.stdout}):start()  -- ls foo/bar
--   local v = Sh'ls foo/bar':start():read()         -- v=$(ls foo/bar)
M.Sh = mty'Sh' {
  "args [table]: arguments to pass to shell",
  "inp [file|string?] shell's stdin to send (default=new pipe)",
  "out [file?]: shell's stdout              (default=new pipe)",
  "err [file?]: shell's stderr              (default=io.stderr)",
  "env [list]:  shell's environment {'FOO=bar', ...}",
  '_sh: C implemented shell',
}
getmetatable(M.Sh).__call = function(T, args, fds)
  local sh = mty.construct(T, fds or {})
  if type(args) == 'string' then args = shim.parseStr(args) end
  sh.args = assert(shim.expand(args), 'must provide args')

  return sh
end
getmetatable(M.Sh).__index = function(sh, k)
  local shv = rawget(sh, '_sh', k)
  if shv then return shv end
  if rawget(sh, '__fields')[k] then return nil end
  error('unknown field: '..k)
end

local function _fnomaybe(f) return f and M.fileno(f) or nil end
-- start the shell in the background.
-- Note: any set filedescriptors will be set to nil.
--       any nil filedescriptors (except stderr) will be set to the new pipe.
M.Sh.start = function(sh)
  local r, w = fd.newFD(), fd.newFD()
  local ex, _r, _w, _lr = lib.sh(
    sh.args[1], sh.args, sh.env,
    _fnomaybe(sh.inp), _fnomaybe(sh.out), M.fileno(sh.err or io.stderr)
  )
  sh._sh = ex
  if _r then r:_setfileno(_r); r:toNonblock() else r = nil end
  if _w then w:_setfileno(_w); w:toNonblock() else w = nil end
  sh.inp, sh.out = w, r
  return sh
end

-- wait for shell to complete, returns return code
M.Sh.wait = function(sh)
  if LAP_ASYNC then
    while not sh:isDone() do yield('sleep', 0.005) end
  else sh._sh:wait() end
  return sh._sh:rc()
end

M.Sh.write = function(sh, ...) return sh.inp:write(...) end
M.Sh.read  = function(sh, ...) return sh.out:read(...) end

-- sh(cmd) -> rc, out
-- Execute the command in another process via execvp (system shell).
--
-- if cmd is a table, the following are treated as special. If you need any
-- of these then you must use M.Sh directly (recommendation: use Piper)
--
--   inp[string|file]: the process's stdin. If string it will be sent to stdin.
--   out[file]: the process's stdout. out will be nil if this is set
--   err[file]: the process's stderr (default=io.stderr)
--
-- Note: use Piper{...}:run() if you want to pipe multiple shells together.
--
-- COMMAND                               BASH
-- sh'ls foo/bar'                     -- ls foo/bar
-- sh{'ls', 'foo/bar', 'dir w spc/'}  -- ls foo/bar "dir w spc/"
-- sh{inp='sent to stdin', 'cat'}     -- echo "sent to stdin" | cat
M.sh = function(cmd)
  local fds, inps
  if type(cmd) == 'table' then local pk = ds.popk
    fds = { inp = pk(cmd,'inp'), out=pk(cmd,'out'), err=pk(cmd,'err') }
  else fds = {} end
  if type(fds.inp) == 'string' then
    if #fds.inp > fd.PIPE_BUF then -- may block, use tmpfile
      local t = fd.tmpfile(); t:write(fds.inp); t:seek'set'
      fd.inp = t
    else inps = fds.inp; fds.inp = nil end
  end
  local sh, out = M.Sh(cmd, fds):start(), nil
  local fns = {
    function() if inps then sh:write(inps) end; sh.inp:close() end,
    function() out = sh:read(); sh.out:close() end,
  }
  if LAP_ASYNC then lap.all(fns) else M.Lap():run(fns) end
  return sh:wait(), out
end


-- Pipe multiple shells together.
-- Piper{inpFile|cmd, ... cmds, outFile?, err=io.stderr}
--
-- These are equivalent:
--   bash:  cat inp.txt |   grep foo.bar >> out.txt
--   Piper{open'inp.txt', 'grep foo.bar', open('out.txt', 'w')}:check()
--
-- All shell operations happen concurrently. Piper properly plumbs the
-- stdout of the prior to stdin to the next. All stderr goes to the same err
-- file (or io.stderr by default)
--
-- The first and last items can be files, in which case they are the inp/out.
-- else, piper can act as a file (with :read()/:write() methods)
M.Piper = mty'Piper' {
  'inp [file]: owned input',
  'out [file]: owned output',
  'err [file]: common stderr',
  -- ... args is the shells to kick off
}

-- TODO: Stream / Pipe / Whatever
-- M.Piper.wait = function(sh)
--   local fns = {
--     function() if sh.inp then w:write(inp) end; w:close() end,
--     function() out =       r:read();         r:close() end,
--   }
--   if LAP_ASYNC then
--     lap.all(fns)
--     while not sh:isDone() do yield('sleep', 0.005) end
--   else
--     M.Lap():start(fns)
--     sh:wait() end
--   return sh:rc(), out
-- 
-- end


return M

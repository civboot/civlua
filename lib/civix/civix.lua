-- civix: unix-like OS utilities.
local M = mod and mod'civix' or {}

local mty  = require'metaty'
local fmt  = require'fmt'
local ds   = require'ds'
local shim = require'shim'
local lib  = require'civix.lib'; local C = lib
local fd   = require'fd'
local lap  = require'lap'

local pth = require'ds.path'
local concat, sfmt = table.concat, string.format
local sort = table.sort
local push, pop = table.insert, table.remove
local yield = coroutine.yield
local pc = pth.concat
local construct = mty.construct

local toDir, toNonDir = pth.toDir, pth.toNonDir
local cmpDirsLast = pth.cmpDirsLast
local fmodeName = fd.FMODE.name

--- Stat object with mode() and modified() functions
M.Stat = C.Stat

--- Given two Stat objects return whether their modifications
--- are equal
M.statModifiedEq = function(fs1, fs2)
  local s1, ns1 = fs1:modified()
  local s2, ns2 = fs2:modified()
  return (s1 == s2) and (ns1 == ns2)
end

--- Given a path|File|Stat return a Stat
M.stat = function(v) --> Stat?, errmsg?
  if getmetatable(v) == M.Stat then return v end
  if type(v) == 'string'       then return lib.stat(v) end
  return lib.stat(fd.fileno(v))
end

--- return whether two Stat's have equal modification times
M.statModifiedEq = function(fs1, fs2) --> boolean
  local s1, ns1 = fs1:modified()
  local s2, ns2 = fs2:modified()
  return (s1 == s2) and (ns1 == ns2)
end

--- return whether two path|File|Stat have equal modification times
M.modifiedEq = function(a, b)
  return M.statModifiedEq(M.stat(a), M.stat(b))
end

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

--- swap paths a <-> b
M.swap = function(a, b, ext)
  ext = ext or '.SWAP'
  M.mv(a, a..ext); M.mv(b, a); M.mv(a..ext, a)
end

--- set the modified time of the path|file
M.setModified = function(f, sec, nsec) --> ok, errmsg?
  local close
  if type(f) == 'string' then f = io.open(f); close = true end
  local ok, err = lib.setmodified(fd.fileno(f), sec, nsec)
  if close then f:close() end
  return ok, err
end

-------------------------------------
-- Utility

--- quote the str if it's possible
M.quote = function(str)
  if string.find(str, "'") then return nil end
  return "'" .. str .. "'"
end

--- "global" shell settings
M.SH_SET = { debug=false, host=false }

-------------------------------------
-- Time Functions

--- Sleep for the specified duration
M.sleep = function(d) --> nil
  if type(d) == 'number' then d = ds.Duration:fromSeconds(d) end
  if d.s >= 0 then lib.nanosleep(d.s, d.ns) end
end

--- Return the Epoch/Mono time
--- Time according to realtime clock
M.epoch   = function() return ds.Epoch(lib.epoch())   end
--- Duration according to monotomically incrementing clock.
M.mono    = function() return ds.Duration(lib.mono()) end
M.monoSec = function() return M.mono():asSeconds()    end

-------------------------------------
-- Core Filesystem

local function qp(p)
  return fmt.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

M.pathtype = function(path)
  local stat, err = lib.stat(path)
  if not stat then return nil, err end
  return fmodeName(C.S_IFMT & stat:mode())
end
M.isFile = function(path) return M.pathtype(path) == 'file' end
M.isDir  = function(path) return M.pathtype(path) == 'dir'  end

local function _walkcall(ftypeFns, path, ftype, err)
  if err then return ftypeFns.error(path, err) end
  local fn = ftypeFns[ftype] or ftypeFns.default
  if fn then return fn(path, ftype) end
end

local function _walk(base, ftypeFns, maxDepth, depth)
  local err
  if maxDepth and depth >= maxDepth then return end
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then
      ftype, err = M.pathtype(path)
      if not ftype then ftype = 'error' end
    end
    local o = _walkcall(ftypeFns, path, ftype, err)
    if o == true then return end
    if o ~= 'skip' and ftype == 'dir' then
      _walk(path, ftypeFns, maxDepth, depth + 1)
    end
  end
  if ftypeFns.dirDone then ftypeFns.dirDone(base, 'dir') end
end

--- TODO: remove this
--- walk the paths up to depth, calling [$ftypeFns[ftype]] for
--- each item encountered.
---
--- If depth is nil/false then the depth is infinite.
---
--- ftypeFns must be a table of ftypes (file, dir) and: [+
---  * default: called as fallback (if missing ftype key)
---  * error: called if determining the type caused an error,
---    typically due to the file not existing.
---    the call is: error(path, errstr)
---  * dirDone: called AFTER the directory has been walked
--- ]
---
--- The Fn signatures are: (path, ftype) -> stopWalk
--- If either return true then the walk is ended immediately
--- If dirFn returns 'skip' then the directory is skipped
M.walk = function(paths, ftypeFns, maxDepth)
  for _, path in ipairs(paths) do
    assert('' ~= path, 'empty path')
    local ftype, err = M.pathtype(path)
    _walkcall(ftypeFns, path, ftype, err)
    if ftype == 'dir' then _walk(path, ftypeFns, maxDepth, 0) end
  end
end

--- Walk the directory tree as a iterator of [$path, ftype]. Can walk either a
--- single path [$Walk'path/'] or a list of paths [$Walk{'a/', 'b.txt'}]. [+
--- * Note: all [$ftype=='dir'] paths end in [$/].
--- * Warning: you may want to handle [$ftype=='error']
--- ]
M.Walk = mty'Walk' {
  'maxDepth [int]: maximum depth to walk (default=infinite)',
  'pi [int]: the current (root) path being walked', pi = 0,
  '_dirs [table]: a stack of WalkDirs that are being walked',
}
getmetatable(M.Walk).__call = function(T, t)
  if type(t) == 'string' then t = {t} end
  t._dirs = {}
  return construct(T, t)
end
---- get the depth of the current directory being walked
M.Walk.depth = function(w) return #w._dirs end
--- skip the current directory level
M.Walk.skip = function(w) pop(w._dirs) end
M.Walk.__call = function(w) --> path, ftype
  local pi = w.pi if pi > #w then return end
  while #w._dirs > 0 do
    local path, err = w._dirs[#w._dirs](w) -- DFS: top of stack
    if path then return path, err end
    pop(w._dirs) -- else _WalkDir is done, pop it.
  end
  pi = pi + 1; w.pi = pi;
  local path = w[pi]; if not path then return end
  local ftype = M.pathtype(path)
  if ftype == 'dir' then path = toDir(path); w:_deeper(path)
  else                   path = toNonDir(path) end
  return path, ftype -- emit the 'root' path
end
--- walk one level deeper by pushing onto _dirs stack.
M.Walk._deeper = function(w, path)
  if not w.maxDepth or #w._dirs <= w.maxDepth then
    push(w._dirs, M._WalkDir{base=path})
  end
end

--- Walk a single directory
M._WalkDir = mty'_WalkDir' {
  'ftypes [table]: path -> ftype map',
  '_i [int]: current index',
  'base [string]: base directory',
}
getmetatable(M._WalkDir).__call = function(T, t)
  local base, ftypes = t.base, {}
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then ftype = M.pathtype(path) end
    path = (ftype=='dir') and toDir(path) or toNonDir(path)
    push(t, path); ftypes[path] = ftype
  end
  sort(t, cmpDirsLast) -- always return files first
  t._i, t.ftypes = 0, ftypes
  return construct(T, t)
end
M._WalkDir.__call = function(wd, walk) --> path, ftype
  local i = wd._i; if i >= #wd then return end
  i = i + 1; wd._i = i
  local path = wd[i]; local ftype = wd.ftypes[path]
  if i > 0 and ftype == 'dir' then walk:_deeper(path) end
  return path, ftype
end

--- A very simple ls (list paths) implementation
--- Returns (files, dirs) tables. Anything that is not a directory
--- is treated as a file.
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
M.mkDirs = function(path)
  if type(path) == 'string' then path = pth(path) end
  local dir = ''; for _, c in ipairs(path) do
    dir = pc{dir, c}
    local ok, errno = lib.mkdir(dir)
    if ok or (errno == C.EEXIST) then -- directory created or exists
    else fmt.errorf('failed to create directory: %s (%s)', 
                    dir, lib.strerrno(errno)) end
  end
end
M.mkDir = function(path, parents) --!!> nil
  if parents then M.mkDirs(pth(path))
  else fmt.assertf(lib.mkdir(path), "mkdir failed: %s", path) end
end

--- mkTree(tree) builds a tree of files and dirs at `dir` [+
--- * Dirs  are tables.
--- * Files are string or fd -- which are read+closed.
--- ]
--- Example: [{## lang=lua}
--- tree = {
---   a = {
---     ['a1.txt'] = 'stuff in a1.txt',
---     ['a2.txt'] = 'stuff in a.txt',
---     a3 = {
---       ['a4.txt'] = io.open'some/file.txt',
---     }
---   }
--- }
--- ]##
---
--- Builds a tree like [#
--- a/a1.txt    # content: stuff in a1.txt
--- a/a2.txt    # content: stuff in a2.txt
--- a/a3/a4.txt # content: stuff in a3.txt
--- ]#
M.mkTree = function(dir, tree, parents) --!!> nil
  M.mkDir(dir, parents)
  for name, v in pairs(tree) do
    local p = pc{dir, name, type(v) == 'table' and '/' or nil}
    if     type(v) == 'table'  then M.mkTree(p, v)
    elseif type(v) == 'string' then pth.write(p, v)
    elseif type(v) == 'userdata' then
      local f = ds.fdMv(io.popen(p, 'w'), v)
      f:close(); v:close()
    else error('invalid tree value of type '..type(v)) end
  end
end

M.Lap = function() return lap.Lap {
  sleepFn=M.sleep, monoFn=M.monoSec, pollList=fd.PollList(),
}end

--- Start args on the shell
--- ["Suggestion: use civix.sh instead.]
---
--- [$Sh:start()] kicks off a subprocess which start the shell using the fds
--- you pass in or creating them if you set them to true. Created file
--- descriptors will be stored in the associated name.
---
--- ["Why? This means that [$:close()] will only close filedescriptors created
---        by the shell itself, and you won't accidentially close
---        io.stdout/etc.]
---
--- Examples (see civix.sh for more examples): [{table}
--- # Lua                                                  | Bash
--- + [$Sh({'ls', 'foo/bar'}, {stdout=io.stdout}):start()] | [$ls foo/bar]
--- + [$v = Sh{'ls foo/bar', stdout=true}:start():read()]  | [$v=$(ls foo/bar)]
--- ]
M.Sh = mty'Sh' {
  "args [table]: arguments to pass to shell",
  "stdin  [file|bool]: shell's stdin to send  (default=empty)",
  "stdout [file|bool]: shell's stdout              (default=empty)",
  "stderr [file|bool]: shell's stderr              (default=empty)",
  "env [list]:  shell's environment {'FOO=bar', ...}",
  "cwd [string]: current working directory",
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
  return f and fd.fileno(f) or default
end
--- start the shell in the background.
--- Example: [$sh{arg1, arg2, stdin=nostdin, stdout=true, stderr=io.stderr}]
--- ["Note: See Sh for how filedescriptors are set]
M.Sh.start = function(sh)
  local r, w, l = fd.newFD(), fd.newFD(), fd.newFD()
  local ex, _r, _w, _l = lib.sh(
    sh.args[1], sh.args, sh.env,
    _fnomaybe(sh.stdin), _fnomaybe(sh.stdout, true),
    _fnomaybe(sh.stderr, fd.sys.STDERR_FILENO),
    sh.cwd
  )
  sh._sh = ex
  if _r then r:_setfileno(_r); r:toNonblock() else r = nil end
  if _w then w:_setfileno(_w); w:toNonblock() else w = nil end
  if _l then l:_setfileno(_l); l:toNonblock() else l = nil end
  sh.stdin, sh.stdout, sh.stderr = w, r, l
  return sh
end

M.Sh.isDone = function(sh) return sh._sh:isDone() end

--- wait for shell to complete, returns return code
M.Sh.wait = function(sh) --> int
  if LAP_ASYNC then
    while not sh:isDone() do yield('sleep', 0.005) end
  else sh._sh:wait() end
  return sh._sh:rc()
end

M.ShFin = mty'ShFin'{
  'stdin [file]', 'stdout [file]', 'stderr [file]',
  "input [string]: write to then close stdin (either self's or shell's)",
}
--- finish files (in sh or other) by writing other.input to stdin and reading
--- stdout/stderr.  All processes are done asynchronously
M.Sh.finish = function(sh, other) --> out, err
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
    sh.env    = pk(cmd, 'ENV')
    sh.cwd    = pk(cmd, 'CWD')
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

--- Execute the command in another process via execvp (system shell). Throws an
--- error if the command fails.
---
--- if cmd is a table, the following keys are treated as special. If you need any
--- of these then you must use M.Sh directly (recommendation: use Plumb) [+
--- * [$stdin[string|file]] the process's stdin. If string it will be sent to stdin.
--- * [$stdout[file]] the process's stdout. out will be nil if this is set
--- * [$stderr[file]] the process's stderr (default=io.stderr)
--- ]
---
--- Note: use [$Plumb{...}:run()] if you want to pipe multiple shells together.
--- [{table}
--- # Command                               Bash
--- + [$sh'ls foo/bar']                    | [$ls foo/bar]
--- + [$sh{'ls', 'foo/bar', 'dir w spc/'}] | [$ls foo/bar "dir w spc/"]
--- + [$sh{stdin='sent to stdin', 'cat'}]  | [$echo "sent to stdin" | cat]
--- ]
M.sh = function(cmd) --> out, err, sh
  local sh, other = M._sh(cmd); sh:start()
  local out, err = sh:finish(other)
  local rc = sh:wait(); if rc ~= 0 then
    fmt.errorf('Command failed with rc=%s: %q%s', rc, cmd,
      (out and (#out > 0) and ('\nSTDOUT:\n'..out) or ''))
  end
  return out, err, sh
end

return M

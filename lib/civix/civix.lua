-- civix: civboot unix utilites.
--
-- Note: You probably want civix.sh
local pkg  = require'pkg'
local mt   = pkg'metaty'
local ds   = pkg'ds'
local shim = pkg'shim'
local lib  = pkg'civix.lib'; local C = lib
local fd   = pkg'fd'
local lap  = pkg'lap'

local path = ds.path
local concat, sfmt = table.concat, string.format
local push, pop = table.insert, table.remove
local yield = coroutine.yield
local pc = path.concat

local M = {
  std_r = 0, std_w = 1, std_lw = 2,
  PIPE_R = io.stdin,
  PIPE_W = io.stdout,
  PIPE_LW = io.stderr,

	-- file types
	SOCK = "sock", LINK = "link",
	FILE = "file", BLK  = "blk",
	DIR  = "dir",  CHR  = "chr",
	FIFO = "fifo",

	dir = lib.dir, rm=lib.rm, rmdir = lib.rmdir,
  exists = lib.exists,

  -- TODO: probably good to catch return code for cross-filesystem
  mv = lib.rename,
}

mt.docTy(M, [[
civix: unix-like OS utilities.
]])

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
M.sleep = mt.doc[[
Sleep for the specified duration.
  sleep(duration)

time can be a Duration or float (seconds).
A negative duration results in a noop.
]](function(d)
  if type(d) == 'number' then d = ds.Duration:fromSeconds(d) end
  if d.s >= 0 then lib.nanosleep(d.s, d.ns) end
end)

-- Return the Epoch/Mono time
M.epoch = mt.doc[[Time according to realtime clock]](
  function() return ds.Epoch(lib.epoch())   end)
M.mono  = mt.doc[[Duration according to monotomically incrementing clock.]](
  function() return ds.Duration(lib.mono()) end)
M.monoSec = function() return M.mono():asSeconds() end

-------------------------------------
-- Core Filesystem

local function qp(p)
  return mt.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
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
  return M.MODE_STR[C.S_IFMT & lib.fstmode(M.fileno(f))]
end

M.pathtype = function(path)
  return M.MODE_STR[C.S_IFMT & lib.stmode(path)]
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
function M.walk(paths, ftypeFns, maxDepth)
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
  print('!! rmRecursive', path);
  M.walk({path}, RMR_FNS, nil)
end
M.mkDirs = function(pthArr)
  local dir = ''; for _, c in ipairs(pthArr) do
    dir = pc{dir, c}
    local ok, errno = lib.mkdir(dir)
    if ok or (errno == C.EEXIST) then -- directory created or exists
    else mt.errorf('failed to create directory: %s (%s)', 
                    dir, lib.strerrno(errno)) end
  end
end
M.mkDir = function(pth, parents)
  if parents then M.mkDirs(path.splitList(pth))
  else mt.assertf(lib.mkdir(pth), "mkdir failed: %s", pth) end
end

M.mkTree = mt.doc[[
mkTree(tree) builds a tree of files and dirs at `dir`.
Dirs  are tables.
Files are string or fd -- which are read+closed.

tree = {
  a = {
    ['a1.txt'] = 'stuff in a1.txt',
    ['a2.txt'] = 'stuff in a.txt',
    a3 = {
      ['a4.txt'] = io.open'some/file.txt',
    }
  }
}

Builds a tree like
a/a1.txt    # content: stuff in a1.txt
a/a2.txt    # content: stuff in a2.txt
a/a3/a4.txt # content: stuff in a3.txt
]](function(dir, tree, parents)
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
end)

M.sh = mt.doc[[
sh(cmd, inp, env) -> rc, out, log
Execute the command in another process via execvp (basically the system shell).

This is the synchronous (blocking) version of this command. Use async.sh for the
asynchronous version (or see 'si' library).

Returns the return-code, out (aka stdout), and log (aka stderr).

COMMAND                               BASH
sh'ls foo/bar'                     -- ls foo/bar
sh{'ls', 'foo/bar', 'space dir/'}  -- ls foo/bar "space dir/"
sh('cat', 'sent to stdin')         -- echo "sent to stdin" | cat
]](function(cmd, inp, env)
  if type(cmd) == 'string' then cmd = shim.parseStr(cmd) end
  cmd = shim.expand(cmd)
  local nfd = fd.sys.newFD
  local r, w, lr = nfd(), nfd(), nfd()
  local sh, _r, _w, _lr = lib.sh(cmd[1], cmd, env)
  r:_setfileno(_r); w:_setfileno(_w); lr:_setfileno(_lr)

  local out, log
  if inp then w:write(inp) end; w:close()
  out = r:read();  r:close()
  log = ''; lr:close() -- log = lr:read(); lr:close()
  -- for _, f in ipairs{r, w, lr} do r:toNonblock() end
  -- M.Lap():run{
  --   function() if inp then w:write(inp) end; w:close() end,
  --   function() out = r:read();  print('!! sh out', out); r:close()              end,
  --   function() log = lr:read(); print('!! sh log', log); r:close()              end,
  -- }
	sh:wait(); return sh:rc(), out, log
end)

return M

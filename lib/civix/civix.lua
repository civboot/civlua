-- civix: civboot unix utilites.
--
-- Note: You probably want civix.sh
local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local shim = pkg'shim'
local lib = pkg'civix.lib'

local path = ds.path
local add, concat, sfmt = table.insert, table.concat, string.format
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

mty.docTy(M, [[
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
M.sleep = mty.doc[[
Sleep for the specified duration.
  sleep(duration)

time can be a Duration or float (seconds).
A negative duration results in a noop.
]](function(d)
  if type(d) == 'number' then d = ds.Duration:fromSeconds(d) end
  if d.s >= 0 then lib.nanosleep(d.s, d.ns) end
end)

-- Return the Epoch/Mono time
M.epoch = mty.doc[[Time according to realtime clock]](
  function() return ds.Epoch(lib.epoch())   end)
M.mono  = mty.doc[[Duration according to monotomically incrementing clock.]](
  function() return ds.Duration(lib.mono()) end)

-------------------------------------
-- Core Filesystem

local function qp(p)
  return mty.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

local C = lib.consts
M.MODE_STR = {
  [C.S_IFSOCK] = 'sock', [C.S_IFLNK] = 'link', [C.S_IFREG] = 'file',
  [C.S_IFBLK]  = 'blk',  [C.S_IFDIR] = 'dir',  [C.S_IFCHR] = 'chr', 
  [C.S_IFIFO]  = 'fifo',
}
lib.methods.Fd.ftype = function(fd)
  return M.MODE_STR[C.S_IFMT & lib.filenostat(fd:fileno())]
end
M.pathtype = function(path)
  return M.MODE_STR[C.S_IFMT & lib.pathstat(path)]
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
    dir     = function(p) add(dirs,  pc{p, '/'}) end,
    default = function(p) add(files, p)          end,
  }, maxDepth)
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
    else mty.errorf('failed to create directory: %s (%s)', 
                    dir, lib.strerrno(errno)) end
  end
end
M.mkDir = function(pth, parents)
  if parents then M.mkDirs(path.splitList(pth))
  else mty.assertf(lib.mkdir(pth), "mkdir failed: %s", pth) end
end

M.mkTree = mty.doc[[
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

M.sh = mty.doc[[
sh(cmd, inp, env) -> rc, out, log
Execute the command in another process via execvp (basically the system shell).

This is the synchronous (blocking) version of this command.
Use async.ash for the async (yielding) version.

Returns the return-code, out (aka stdout), and log (aka stderr).

COMMAND                               BASH
sh'ls foo/bar'                     -- ls foo/bar
sh{'ls', 'foo/bar', 'space dir/'}  -- ls foo/bar "space dir/"
sh('cat', 'sent to stdin')         -- echo "sent to stdin" | cat
]](function(cmd, inp, env)
  if type(cmd) == 'string' then cmd = shim.parseStr(cmd) end
  cmd = shim.expand(cmd)
  local sh, r, w, lr = lib.sh(cmd[1], cmd, env)
  mty.pnt('!! lib.sh sh=', sh, 'r=', r, 'w=', w, 'lr=', lr);
  if inp then lib.fdwrite(w, inp) end; w:close()
	local out, log = lib.fdread(r), lib.fdread(lr)
  r:close(); lr:close()
	sh:wait(); return sh:rc(), out, log
end)

return M

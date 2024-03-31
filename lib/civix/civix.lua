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

	dir = lib.dir, ftype = lib.ftype,
}

mty.docTy(M, [[
civix: unix-like OS utilities.
]])

mty.docTy(lib.ftype, [[
ftype(path) -> ftype

ftype is one of:
  file, dir            : standard file / directory
  link                 : symbolic link
  sock, blk, chr, fifo : see unix inode(7) st_mode field
]])

M.posix = mty.want'posix'
if M.posix then
  assert(M.std_r  == M.posix.fileno(io.stdin))
  assert(M.std_w  == M.posix.fileno(io.stdout))
  assert(M.std_lw == M.posix.fileno(io.stderr))
end

-------------------------------------
-- Utility

-- quote the str if it's possible
M.quote = function(str)
  if string.find(str, "'") then return nil end
  return "'" .. str .. "'"
end

-- return (read('*a'), {close()})
M.lsh = mty.doc[[execute via io.popen(c, 'r')
returns stdout, {ok, msg, rc} aka fd:close()
If allowError is false asserts that ok == true
]](function(c, allowError)
  local f = assert(io.popen(c, 'r'), c)
  local o, r = f:read('*a'), {f:close()}
  assert(r[1] or allowError, r[2])
  return o, r
end)

-- "global" shell settings
M.SH_SET = { debug=false, host=false }

-------------------------------------
-- Time Functions

-- Sleep for a duration
M.sleep = function(duration)
  if type(duration) == 'number' then
    duration = ds.Duration:fromSeconds(duration)
  end
  if M.posix then M.posix.nanosleep(duration.s, duration.ns)
  else M.lsh('sleep '..tostring(duration)) end
end

-- Return the Epoch time
M.epoch = function()
  return ds.Epoch(lib.epoch())
end

-------------------------------------
-- Core Filesystem

local function qp(p)
  return mty.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

local function handleFtype(ftypeFns, path, ftype)
  local fn = ftypeFns[ftype] or ftypeFns.default
  if fn then return fn(path, ftype) end
end

local function _walk(base, ftypeFns, maxDepth, depth)
  if maxDepth and depth >= maxDepth then return end
  for fname, ftype in M.dir(base) do
    local path = pc{base, fname}
    if ftype == 'unknown' then ftype = M.ftype(path) end
    local o = handleFtype(ftypeFns, path, ftype)
    if o == true then return end
    if o ~= 'skip' and ftype == 'dir' then
      _walk(path, ftypeFns, maxDepth, depth + 1)
    end
 	end
end


-- walk the paths up to depth, calling fileFn for each file and dirFn for each
-- directory. If depth is nil/false then it is infinite.
--
-- The Fn signatures are: (path, depth) -> stopWalk
-- If either return true then the walk is ended immediately
-- If dirFn returns 'skip' then the directory is skipped
function M.walk(paths, ftypeFns, maxDepth)
  for _, path in ipairs(paths) do
    assert('' ~= path, 'empty path')
    local ftype = M.ftype(path); handleFtype(ftypeFns, path, ftype)
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

M.mv = function(from, to) M.lsh(sfmt('mv %s %s', qp(from), qp(to))) end
M.rm = function(path) M.lsh('rm '..qp(path)) end
M.rmDir = function(path, children)
  if children then M.lsh('rm -r '..qp(path))
  else             M.lsh('rmdir '..qp(path)) end
end
M.mkDir = function(path, parents)
  if parents then M.lsh('mkdir -p '..qp(path))
  else            M.lsh('mkdir '..qp(path)) end
end
M.exists = function(path)
  local _, r = M.lsh('test -e '..qp(path), true)
  return r[3] == 0
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
  local s, r, w, lr = lib.sh(cmd[1], cmd, env)
  if inp then w:write(inp) end; w:close()
  local out, log, o, l = {}, {}
  while not s:isDone() do
    o, l = r:read'a', lr:read'a'
    if o ~= '' then push(out, o) end
    if l ~= '' then push(log, l) end
  end
  r:close(); lr:close(); s:wait()
  return s:rc(), table.concat(out), table.concat(log)
end)

return M

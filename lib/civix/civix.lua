-- civix: civboot unix utilites.
--
-- Note: You probably want civix.sh
local pkg = require'pkg'
local mt = pkg'metaty'
local ds = pkg'ds'
local da = pkg'ds.async'
local shim = pkg'shim'
local lib = pkg'civix.lib'

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

-------------------------------------
-- Core Filesystem

local function qp(p)
  return mt.assertf(M.quote(p), 'path cannot contain "\'": %s', p)
end

local C = lib.consts
M.MODE_STR = {
  [C.S_IFSOCK] = 'sock', [C.S_IFLNK] = 'link', [C.S_IFREG] = 'file',
  [C.S_IFBLK]  = 'blk',  [C.S_IFDIR] = 'dir',  [C.S_IFCHR] = 'chr', 
  [C.S_IFIFO]  = 'fifo',
}
local function _ftype(f)
  return M.MODE_STR[C.S_IFMT & lib.filenostat(f:fileno())]
end
local I = lib.indexes
I.Fd.ftype   = _ftype;
I.FdTh.ftype = _ftype;
I.Fd.read = function(fd, num)
  lib.fdread(fd, ds.min(lib.IO_SIZE, num))
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

-------------------------------------
-- PollList

M.PollList = mt.record'PollList'
  :field'map':fdoc'map of fileno -> pl[index]'
  :field'avail':fdoc'list of available indexes'
  :field('size', 'number')
  :field'_pl'
:new(function(ty_, size)
  mt.pnt('!! PollList', ty_, size)
  local pl = mt.new(ty_, {
    map={}, avail={}, size=0, _pl=lib.polllist(),
  })
  if size then pl:resize(size) end
  return pl
end)

M.PollList.__len = function(pl) return pl.size - #pl.avail end

M.PollList.resize = function(pl, newSize)
  local size = pl.size; assert(newSize >= size, 'attempted shrink')
  pl._pl:resize(newSize); pl.size = newSize
  for i=size,newSize-1 do push(pl.avail, i) end
end

M.PollList.insert = function(pl, fileno, events)
  local i = pl.map[fileno] or pop(pl.avail)
  if not i then
    pl:resize((pl.size == 0) and 8 or pl.size * 2)
    i = assert(pop(pl.avail))
  end
  pl._pl:set(i, fileno, events)
  pl.map[fileno] = i
end

M.PollList.remove = function(pl, fileno)
  local i = assert(pl.map[fileno], 'fileno not tracked')
  pl._pl:set(i, -1, 0)
  pl.map[fileno] = nil; push(pl.avail, i)
end

M.PollList.ready = function(pl) return pl._pl:ready() end

-------------------------------------
-- File

local function readAll(f, mode)
  local data = {}
  while true do
    local o, err = f:_read(); if err then error(err) end
    if o then
      push(data, o)
      if #o == 0 then break end
    else yield(da.poll(f:fileno(), C.POLLIN)) end
  end
  data = table.concat(data)
  return #data > 0 and data or nil
end

local function readAmount(f, amt)
  local data = {}
  while amt > 0 do
    local o, err = f:_read(math.min(amt, C.IO_SIZE))
    if err then error(err) end
    if o then
      push(data, o); amt = amt - #o
      if #o == 0 then break end
    else yield(da.poll(f:fileno(), C.POLLIN)) end
  end
  data = table.concat(data)
  return #data > 0 and data or nil
end

local linesError = function()
  error'options l/L not supported. Use file:lines()'
end
local READ_MODE = {
  a=readAll, ['a*']=readAll, l=linesError, L=linesError,
}

M.read = function(f, mode)
  if type(mode) == 'number' then return readAmount(f, mode) end
  local fn = mt.assertf(READ_MODE[mode],
    'unrecognized mode: %s', mode)
  return fn(f, mode)
end

M.write = function(f, s)
  local i = 1; while i <= #s do
    local pos, err = f:_write(s, i); if err then error(err) end
    if pos then
      if pos <= i then break end
      i = pos
    else yield(da.poll(f:fileno(), C.POLLOUT)) end
  end
end

-- (buf) -> (indexInclude, indexRemain)
local LINES_END = {l=-1, L=0}
M.lines = mt.doc[[
lines(file, mode='l') -> modeIter
Identical to io.lines but buffers in Lua (meaning the seek position
will probably be incorrect).

Supported Modes:
 * 'l' -> iterator of lines with the newline characters omitted
 * 'L' -> iterator of lines including newline characters

Note: other modes (like 'a' or integers) are not supported.
]](function(f, mode)
  mode = assert(LINES_END[mode or 'l'], 'unrecognized mode')
  local buf, lines = {}, {}
  return function()
    if not lines then return end
    while #lines == 0 do ::loop::
      local s = f:read(C.IO_SIZE)
      if not s then -- EOF
        push(buf, s); s = table.concat(buf)
        buf, lines = nil, nil
        return (#s > 0) and s or nil
      end
      local nl = s:find'\n'; if not nl then goto loop end
      push(buf, s:sub(1, nl + mode))
      push(lines, table.concat(buf)); buf = {}
      local st = nl + 1
      while st < #s do
        nl = s:find('\n', st); if nl then
          push(lines, s:sub(st, nl + mode))
          st = nl + 1
        else break end
      end
      push(buf, pop(lines)) -- last item in "lines" had no newline
      ds.reverse(lines); assert(#lines > 0)
    end
    return pop(lines)
  end
end)

I.Fd.read   = M.read
I.Fd.write  = M.read
I.Fd.lines  = M.lines

-------------------------------------
-- Async functions

M.async = {}
M.async.open = function(path, mode)

end

M.block = {
  open = io.open,
}

M.block.sh = mt.doc[[
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
  local sh, r, w, lr = lib.sh(cmd[1], cmd, env)
  if inp then w:_write(inp) end; w:close()
	local out, log = r:_read(), lr:_read()
  r:close(); lr:close()
	sh:wait(); return sh:rc(), out, log
end)

-- TODO: this doesn't actually work yet, but
-- is a sketch of how I WANT the API to work.
local function howIWantSh(cmd, inp, env)
  if type(cmd) == 'string' then cmd = shim.parseStr(cmd) end
  cmd = shim.expand(cmd)
  local sh, r, w, lr = lib.sh(cmd[1], cmd, env)
  alwaysNonBlocking(r, w, lr)
  local out, log = {}, {}

  -- blocking implementation
  local threads = {
    [r:fileno()] = function() push(out, r:read'a') end,
    [w:fileno()] = function() w:write(inp)         end,
    [l:fileno()] = function() push(log, lr:read'a') end,
  }
  local pl = M.PollList(3)
  pl:insert(r:fileno(),  C.POLLIN); pl:insert(rl:fileno(), C.POLLIN);
  pl:insert(w:fileno(),  C.POLLOUT);
  while #pl > 0 do
    for fno in ipairs(pl:ready(-1)) do
      threads[fno]()
    end
  end
  return table.concat(out), table.concat(log)
end

M.sh = M.block.sh

return M

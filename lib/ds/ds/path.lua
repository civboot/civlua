local G = G or _G

--- working with paths
--- Call directly to convert a list|str to a list of path components.
local M = G.mod and mod'ds.path' or setmetatable({}, {__name='ds.path'})

local mty = require'metaty'
local ds = require'ds'
local push = table.insert
local sfmt = string.format
local update = table.update

local extend, splitList = ds.extend, ds.splitList
local clear, ds_rmleft  = ds.clear, ds.rmleft

--- read file at path or throw error
M.read = function(path) --!!> string
  local f, err, out = io.open(path, 'r'); if not f then error(sfmt(
    "open %q mode=r: %s", path, err
  ))end
  out, err = f:read'a'; f:close()
  if not out then error(sfmt('read %s: %s', path, err)) end
  return out
end

--- write string to file at path or throw error
M.write = function(path, text) --!!> nil
  local f, err, out = io.open(path, 'w'); if not f then error(sfmt(
    "open %q mode=w: %s", path, err
  ))end
  out, err = f:write(text); f:close(); assert(out, err)
end

getmetatable(M).__call = function(_, p)
  if type(p) == 'table' then return p end
  p = splitList(p, '/+')
  if p[1] == ''  then p[1] = '/' end
  local len = #p
  if len > 1 and p[len] == '' then
    p[len - 1] = p[len - 1]..'/'; p[len] = nil
  end
  return p
end

--- get current working directory
M.cwd = function() return G.CWD or os.getenv'PWD' or os.getenv'CD' end

--- get the user's home directory
M.home = function() return G.HOME or os.getenv'HOME'
                        or os.getenv'HOMEDIR'      end

--- join a table of path components
M.concat = function(t) --> string
  if #t == 0 then return '' end
  local root = (t[1]:sub(1,1)=='/') and '/' or ''
  local dir  = (t[#t]:sub(-1)=='/') and '/' or ''
  local out = {}
  for i, p in ipairs(t) do
    p = string.match(p, '^/*(.-)/*$')
    if p ~= '' then push(out, p) end
  end; return root..table.concat(out, '/')..dir
end

--- return whether a path has any '..' components
M.hasBacktrack = function(path) --> bool. path: [str|list]
  if type(path) == 'string' then
    return path:match'^%.%.$' or path:match'^%.%./'
        or path:match'/%.%./' or path:match'/%.%.$'
  end
  for _, c in ipairs(path) do
    if c == '..' then return true end
  end; return false
end
M.ext = function(path) --> string. path: [str|list]
  if type(path) == 'table' then path = path[#path] end
  return path:match'.*%.([^/]+)$'
end

--- E-nsure the path is absolute, using the wd (default=cwd()) if necessary
---
--- This preserves the type of the input: str -> str; table -> table
M.abs = function(path, wd) --> /absolute/path
  if type(path) == 'string' then
    if (path:sub(1,1) == '/') then return path end
    wd = wd or M.cwd()
    return (wd:sub(-1) == '/') and (wd..path)
                               or  (wd..'/'..path)
  end
  if path[1]:sub(1,1) == '/' then return path end
  assert(type(wd) == 'string')
  return extend(M(wd), path)
end

--- resolve any `..` or `.` path components, making the path
--- /absolute if necessary.
M.resolve = function(path, wd) --> list
  if type(path) == 'table' then path = update({}, path)
  else path = M(path) end

  -- walk path, resolving . and ..
  local i, j, len, last = 1, 1, #path, path[#path]
  local isdir = last:sub(-1) == '/' or last:match'^/?%.%.?$'
  while j <= len do
    local c = path[j]
    if c == '' or c:match'^/?%./?$'   then j = j + 1 -- '.'  skip
    elseif        c:match'^/?%.%./?$' then           -- '..' backtrack
      i = i - 1; j = j + 1
      if i <= 1 then
        assert(path[1]:sub(-1) ~= '/', '../ backtrack before root')
      end
      if i < 1 then
        local abs = M(wd or M.cwd())
        len = #abs
        table.move(path, j, #path + 1, len, abs)
        i, j      = len, len
        path, len = abs, #abs
      end
    else
      path[i] = path[j]
      i = i + 1; j = j + 1
    end
  end
  clear(path, i, len)
  len = #path; last = path[#path]
  if isdir and last and last:sub(-1) ~= '/' then
    path[len] = last..'/'
  end
  return path
end

M.itemeq = function(a, b) --> boolean: path items are equal
  return a:match'^/*(.-)/*$' == b:match'^/*(.-)/*$'
end

--- ds.rmleft for path components
M.rmleft = function(path, rm)
  return ds_rmleft(path, rm, M.itemeq)
end

--- return a nice path (string) that is resolved and readable.
---
--- It's 'nice' because it has no '/../' or '/./' elements
--- and has CWD stripped.
M.nice = function(path, wd) --> string
  wd = wd or M.cwd()
  path, wd = M.resolve(path, wd), M(wd)
  M.rmleft(path, wd)
  if #path == 0 or path[1] == '' then path[1] = './' end
  return M.concat(path)
end

--- Return only the parent dir and final item.
--- This is often used for documentation/etc
M.short = function(path, wd)
  return M.nice(path, wd):match'([^/]*/[^/]+)'
end

--- [$first/middle/last -> ("first", "middle/last")]
M.first = function(path)
  if path:sub(1,1) == '/' then return '/', path:sub(2) end
  local a, b = path:match('^(.-)/(.*)$')
  if not a or a == '' or b == '' then return path, '' end
  return a, b
end

--- [$first/middle/last -> ("first/middle", "last")]
M.last = function(path)
  local a, b = path:match('^(.*/)(.+)$')
  if not a or a == '/' or b == '' then return '', path end
  return a, b
end

--- return whether the path looks like a dir.
--- Note: civlua tries to make all ftype='dir' paths end in '/'
---   but other libraries or APIs may not conform to this.
M.isDir = function(path) return path:sub(-1) == '/' end
local isDir = M.isDir
M.toDir = function(path) --> path/
  return (path:sub(-1) ~= '/') and (path..'/') or path
end

M.toNonDir = function(path) --> path (without ending /)
  return (path:sub(-1) == '/') and path:sub(1,-2) or path
end

--- path comparison function for [$table.sort] that sorts
--- dirs last, else alphabetically.
M.cmpDirsLast = function(a, b)
  if isDir(a) then
    if isDir(b) then return a < b end
    return false
  elseif isDir(b) then return true end
  return a < b
end

return M

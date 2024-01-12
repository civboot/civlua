-- pkg: better lua pkg creation and importing
-- usage:
--   local pkg = require'pkg'
--   local myMod = pkg'myMod'

local push, sfmt = table.insert, string.format
local M = {}

M.PKGS = {} -- loaded pkgs

-- These are modified before loading the package.
-- The package can inspect it to (for example) know it's version string,
-- i.e. local version = require'pkg'.PKG.version
--
-- It is recommended to do this before executing any other `pkg()` calls!
M.PKG  = nil -- PKG.lua being loaded
M.PATH = nil -- path to lua file being loaded

M.CHUNK_SIZE = 4096

-- reduced math (no randomness)
M.MATH = {
  abs=math.abs, ceil=math.ceil, floor=math.floor,
  max=math.max, min=math.min,
  maxinteger=math.maxinteger, tonumber=tonumber,
}
M.math = setmetatable(M.MATH, {
  __index   = function(self, i) return M.MATH[i] end,
  __newindex= function() error'cannot modify math' end,
})


M.ENV = {
  string=string, table=table, utf8=utf8,
  type=type,   select=select,
  pairs=pairs, ipairs=ipairs, next=next,
  error=error, assert=assert,
  math=M.math,
}

M.createEnv = function(env, new)
  new = new or {}
  new.__index = function(e, i) return env[i] end
  return setmetatable(new, env)
end

M.callerSource = function()
  local info = debug.getinfo(3)
  return string.format('%s:%s', info.source, info.currentline)
end

-- loadraw(chunk, env) -> ok, result
M.loadraw = function(chunk, env, name)
  name = name or M.callerSource()
  local res = setmetatable({}, env)
  local e, err = load(chunk, path, 'bt', res)
  if err then return false, err end
  e()
  return true, setmetatable(res, nil)
end

-- load a path with env metatable M.ENV
M.load = function(path, env)
  local f =io.open(path); if not f then error(
    'failed to open: '..path
  )end
  local function chunk() return f:read(M.CHUNK_SIZE) end
  local ok, res = M.loadraw(chunk, M.createEnv(M.ENV, env or {}), path)
  f:close(); return ok, res
end

--------------------
-- Working with file paths
M.path = {}

-- join a table of path components
M.path.concat = function(t)
  if #t == 0 then return '' end
  local root = (t[1]:sub(1,1)=='/') and '/' or ''
  local dir  = (t[#t]:sub(-1)=='/') and '/' or ''
  local out = {}
  for i, p in ipairs(t) do
    p = string.match(p, '^/*(.-)/*$')
    if p ~= '' then push(out, p) end
  end; return root..table.concat(out, '/')..dir
end


M.path.first = function(path)
  if path:sub(1,1) == '/' then return '/', path:sub(2) end
  local a, b = path:match('^(.-)/(.*)$')
  if not a or a == '' or b == '' then return path, '' end
  return a, b
end

M.path.last = function(path)
  local a, b = path:match('^(.*)/(.+)$')
  if not a or a == '' or b == '' then return '', path end
  return a, b
end

-- return whether a path has any '..' components
M.path.hasBacktrack = function(path)
  return string.match'^%.%.$' or string.match'^%.%./'
      or string.match'/%.%./' or string.match'/%.%.$'
end

-- recursively find a package in dirs
M.findpkg = function(base, dirs, name)
  local root = name:match'(.*)%.' or name
  for _, dir in ipairs(dirs) do
    local pkgdir = base and M.path.concat{base, dir} or dir
    local path = M.path.concat{pkgdir, 'PKG.lua'}
    local ok, pkg = M.load(path); if not ok then error(pkg) end
    if (pkg.name == root) then return pkgdir, pkg end
    if pkg.dirs then
      local subdir, subpkg = M.findpkg(pkgdir, pkg.dirs, name)
      if subpkg then return subdir, subpkg end
    end
  end
end

-- auto-set nil locals using mod
-- local x, y, z; pkg.auto'mm' -- sets x=mm.x; y=mm.y; z=mm.z
M.auto = function(mod, i)
  mod, i = type(mod) == 'string' and M(mod) or mod, i or 1
  while true do
    local n, v = debug.getlocal(2, i)
    if not n then break end
    if nil == v then
      if not mod[n] then error(n.." not in module") end
      debug.setlocal(2, i, mod[n])
    end
    i = i + 1
  end
  return mod, i
end

-- Load the package or get nil and and errorMsg
-- fallback will be called on failure (use true for `require`), the error
-- message will still be returned even if fallback is called.
--
-- Usage:
--   pkg.maybe'foo' -> fooPkg, errorMsg
M.maybe = function(name, fallback)
  if (fallback == nil) or (fallback == true) then fallback = require end
  if package.loaded[name] then return package.loaded[name] end
  local luapkgs = assert(os.getenv'LUA_PKGS', 'must export LUA_PKGS')
  local dirs = {''}; for d in luapkgs:gmatch'[^;]+' do push(dirs, d) end
  local pkgdir, pkg = M.findpkg(nil, dirs, name)
  if not pkg then return fallback and fallback(name) or nil,
                         'PKG '..name..' not found' end
  for k, v in ipairs(pkg.srcs) do
    local mpath, mname; if type(k) == 'string' then
      mpath, mname = v, k
    elseif type(k) == 'number' then
      mpath, mname = v, v:gsub('.%lua$', ''):gsub('/', '.')
    else error('invalid srcs key type: '..type(k)) end
    if mname == name then
      M.PKG, M.PATH = pkg, M.path.concat{pkgdir, mpath}
      package.loaded[mname] = dofile(M.PATH)
      return package.loaded[mname]
    end
  end
  return fallback and fallback(name) or nil,
         'PKG found but not sub-module: '..name
end

local MT = {}
MT.__call = function(_, name, fallback)
  local pkg, errMsg = M.maybe(name, fallback); if pkg then return pkg end
  error(errMsg)
end

return setmetatable(M, MT)

-- pkg: better lua pkg creation and importing
-- usage:
--   require'pkglib'.install()

local push, sfmt = table.insert, string.format
local M = {require=require}

-- Documentation globals
local weakk = {__name='DocGlobal', __mode='k'}
DOC_LOC  = DOC_LOC  or setmetatable({}, weakk)
DOC_NAME = DOC_NAME or setmetatable({}, weakk)

-- pkg.UNAME is the platform, typically: Windows, Linux or Darwin
if package.config:sub(1,1) == '\\' then
  M.UNAME = 'Windows'
else
  local f = io.popen'uname'; M.UNAME = f:read'*a':match'%w+'; f:close()
end

-------------------
-- Internal utility functions

local function passert(p)
  if #p == 0           then error('empty path')                          end
  if p:sub(1,1) == '/' then error('root path (/a/b) not permitted: '..p) end
  if p:match('%.%.')   then error('backtrack (/../) not permitted: '..p) end
end
local function pjoin(a, b) --> a/b
  if b:sub(1,1) then sfmt('root path not permitted: %s', b) end
  a = a:sub(-1) == '/' and a:sub(1, -2) or a
  return sfmt('%s/%s', a, b)
end

-------------------
-- Library constants / etc

-- Helper for PKG.lua files loading compiled dynamic libraries
M.LIB_EXT = '.so'; if M.UNAME == 'Windows' then M.UNAME = '.dll' end

M.PKGS = false -- loaded pkgs

-- These are modified before loading the package.
-- The package can inspect it to (for example) know it's version string,
-- i.e. local version = require'pkglib'.PKG.version
--
-- It is recommended to do this before executing any other `pkg()` calls!
M.PKG  = nil -- PKG.lua being loaded
M.PATH = nil -- path to lua file being loaded

M.ENV = {
  UNAME=UNAME,   LIB_EXT=M.LIB_EXT,
  format=string.format,
  insert=table.insert, sort=table.sort, concat=table.concat,
  pairs=pairs,   ipairs=ipairs,
  error=error,   assert=assert,
}; M.ENV.__index = M.ENV

-------------------
-- Compile + Run (load) paths
local loaderr = function(name, path, err)
  error(string.format('loading pkg %s at %s: %s', name, path, err))
end

-- load(path) -> globals
M.load = function(name, path)
  local env = setmetatable({}, M.ENV)
  local pkg, err = loadfile(path, nil, env)
  if not pkg then loaderr(name, path, err) end
  pkg()
  return env
end

-- load(path, name) -> calls exported (native) luaopen_name() to get
--   native module.
M.loadlib = function(name, path)
  local pkg, err = package.loadlib(path, 'luaopen_'..name:gsub('%.', '_'))
  if not pkg then loaderr(name, path, err) end
  return pkg()
end

-------------------
-- Finding
local function _discover(pkgdir)
  local pkg = M.load('PKG', pjoin(pkgdir, 'PKG.lua'))
  if pkg.name:find'%.' then
    error("pkg name cannot contain '.': "..pkg.name)
  end
  M.PKGS[pkg.name] = pkgdir
  if not pkg.pkgs then return end
  for _, dir in ipairs(pkg.pkgs) do
    passert(dir)
    _discover(pjoin(pkgdir, dir))
  end
end
M.discover = function(luapkgs)
  M.PKGS = {}
  local pkgs = {'.'}; for d in luapkgs:gmatch'[^;]+' do push(pkgs, d) end
  for _, dir in ipairs(pkgs) do _discover(dir) end
end

-------------------
-- Loading

-- get the package. The API is identical to 'require' except
-- it uses LUA_PKGS to search.
M.get = function(name, fallback)
  fallback = (fallback == nil) and M.require or fallback
  local mod = package.loaded[name]; if mod then return mod end
  if not M.PKGS then
    M.discover(assert(os.getenv'LUA_PKGS' or '', 'must export LUA_PKGS'))
  end
  -- use fallback if pkg doesn't exist
  local pkgname = name:match'(.*)%.' or name
  local pkgdir = M.PKGS[pkgname]
  if not pkgdir then
    if fallback then return fallback(name) end
    error(sfmt('name %s (pkgname=%q) not found', name, pkgname))
  end
  local pkg = M.load(pkgname, pjoin(pkgdir, 'PKG.lua'))
  local k, mname, mpath
  -- search in srcs for lua modules
  while true do k, mpath = next(pkg.srcs, k)
		if not k then break end
    if type(k) == 'string'     then mname = mpath
    elseif type(k) == 'number' then
		  mname = mpath:gsub('.%lua$', ''):gsub('/', '.')
    else error('invalid srcs key type: '..type(k)) end
    passert(mpath)
    if mname == name and mpath:match'%.lua$' then
      package.loaded[mname] = dofile(pjoin(pkgdir, mpath))
      return package.loaded[mname]
    end
  end
  -- search in libs for dynamic libraries
  for mname, mpath in pairs(pkg.libs or {}) do
    passert(mpath)
    package.loaded[mname] = M.loadlib(mname, pjoin(pkgdir, mpath))
    return package.loaded[mname]
  end
  error(sfmt('PKG %s found but not sub-module %q', pkgname, name))
end

-----------------------
-- MOD
local srcloc = function(level)
  local tb  = debug.traceback(nil, 2 + (level or 0))
  return assert(tb:match'.*traceback:%s+([^\n]*:%d+)')
end

local CONCRETE_TYPE = {
  ['nil']=true, bool=true, number=true, string=true,
}

-----------------------
-- MOD
do
  -- mod(name) -> Mod{}: create a typesafe mod
  local modloc, mod = srcloc(), {}
  DOC_LOC[mod] = modloc; DOC_NAME[mod] = 'mod'
  mod.__name='Mod'
  mod.__index=function(m, k) error('mod does not have: '..k, 2) end
  mod.__newindex=function(t, k, v)
    rawset(t, k, v)
    if type(k) ~= 'string' or CONCRETE_TYPE[type(v)] then return end
    if DOC_LOC[v] or DOC_NAME[v] then return end
    DOC_LOC[v]  = srcloc(1)
    DOC_NAME[v] = t.__name..'.'..k
    if(type(v)) == 'table' and rawget(v, '__name') == true then
      rawset(v, '__name', k)
    end
  end
  M.mod = setmetatable(mod, {
    __name='Ty<Mod>',
    __call=function(T, name)
      assert(type(name) == 'string', 'must provide name str')
      local m = setmetatable({__name=name}, T)
      DOC_NAME[m], DOC_LOC[m] = name, srcloc(1)
      return m
    end,
  })
end

-- override globals {require, mod}
M.install = function()
  require = M.get
  mod     = M.mod
end

return setmetatable(M, {
  __call = function(p, ...) return M.get(...) end,
  __index = function(_, k) error('pkg does not have field: '..k) end,
  __newindex = function(_, k) error'do not modify pkg'           end,
})

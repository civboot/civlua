-- pkg: better lua pkg creation and importing
-- usage:
--   require'pkglib'.install()

local push, sfmt = table.insert, string.format
local M = {require=require}

-- Documentation globals
local weakk = {__mode='k'}
PKG_NAMES  = PKG_NAMES  or setmetatable({}, weakk)        -- obj -> name
PKG_LOC   = PKG_LOC   or setmetatable({}, weakk)        -- obj -> path:loc
PKG_LOOKUP = PKG_LOOKUP or setmetatable({}, {__mode='v'}) -- name -> obj

-- pkg.UNAME is the platform, typically: Windows, Linux or Darwin
if package.config:sub(1,1) == '\\' then
  M.UNAME = 'Windows'
else
  local f = io.popen'uname'; M.UNAME = f:read'*a':match'%w+'; assert(f:close())
end

-------------------
-- Internal utility functions

local function pexists(p)
  local f = io.open(p)
  return f and (f:close() or true) or false
end
local function passert(p)
  if type(p) == 'table' then return p end -- no validation on tables
  if #p == 0           then error('empty path')                          end
  if p:sub(1,1) == '/' then error('root path (/a/b) not permitted: '..p) end
  if p:match('%.%.')   then error('backtrack (/../) not permitted: '..p) end
  return p
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
M.load = function(name, path); assert(name and path)
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
  local pkgpath = pjoin(pkgdir, 'PKG.lua')
  if not pexists(pkgpath) then return end
  local pkg = M.load('PKG', pkgpath)
  if pkg.name:find'%.' then
    error("pkg name cannot contain '.': "..pkg.name)
  end
  M.PKGS[pkg.name] = pkgdir
  if not pkg.pkgs then return end
  for _, dir in ipairs(pkg.pkgs) do
    _discover(pjoin(pkgdir, passert(dir)))
  end
end
M.discover = function(luapkgs)
  M.PKGS = {}
  local pkgs = {'.'}; for d in luapkgs:gmatch'[^;]+' do push(pkgs, d) end
  for _, dir in ipairs(pkgs) do _discover(dir) end
end

-------------------
-- Loading

-- modules(PKG.srcs) -> map[name -> path]
M.modules = function(pkgsrcs)
  local mods = {}
  for mname, mpath in pairs(pkgsrcs) do
    if     type(mname) == 'string' then -- already set
    elseif type(mname) == 'number' then
		  mname = mpath:gsub('%.lua$', ''):gsub('/', '.')
    else error('invalid srcs key type: '..type(mname)) end
    mods[mname] = passert(mpath)
  end
  return mods
end

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
  -- search in srcs for lua modules
  for mname, mpath in pairs(M.modules(pkg.srcs)) do
    if mname == name and type(mpath) == 'string' and mpath:match'%.lua$' then
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
local CONCRETE_TYPE = {
  ['nil']=true, bool=true, number=true, string=true,
}
local srcloc = function(level)
  local tb  = debug.traceback(nil, 2 + (level or 0))
  return assert(tb:match'.*traceback:%s+([^\n]*:%d+)')
end

-- mod(name) -> Mod{}: create a typosafe mod
do local modloc = srcloc()
  M.mod = {}
  PKG_LOC[M.mod] = modloc; PKG_NAMES[M.mod] = 'mod'; PKG_LOOKUP.mod = M.mod
  M.mod.__name='Mod'
  M.mod.__index=function(m, k) error('mod does not have: '..k, 2) end
  M.mod.__newindex=function(t, k, v)
    rawset(t, k, v)
    if type(k) ~= 'string' then return end
    local n = rawget(t, '__name')
    M.mod.save(t.__name..'.'..k, v)
  end

  -- member function (not method)
  -- save v with name to PKG variables
  M.mod.save = function(name, v)
    if CONCRETE_TYPE[type(v)] then return end
    PKG_LOC[v]  = PKG_LOC[v]  or srcloc(2)
    PKG_NAMES[v] = PKG_NAMES[v] or name
    PKG_LOOKUP[name] = PKG_LOOKUP[name] or v
  end

  setmetatable(M.mod, {
    __name='Ty<Mod>',
    __call=function(T, name)
      assert(type(name) == 'string', 'must provide name str')
      local m = setmetatable({__name=name}, {
        __name=sfmt('Ty<%s>', name),
        __index=M.mod.__index,
        __newindex=M.mod.__newindex,
      })
      M.mod.save(name, m)
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
  __index = function(_, k) error('pkglib does not have field: '..k) end,
  __newindex = function(_, k) error'do not modify pkg'           end,
})

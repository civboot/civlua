-- pkg: better lua pkg creation and importing
-- usage:
--   require'pkglib'()

local push, sfmt = table.insert, string.format
local M = setmetatable({}, {
  __name='Mod<pkglib>',
  __index = function(_, k) error('pkglib does not have field: '..k) end,
})

-- cache globals / fallback
M.requireBuiltin = require

-- Documentation globals
local weakk = {__mode='k'}
PKG_NAMES  = PKG_NAMES  or setmetatable({}, weakk)        -- obj -> name
PKG_LOC    = PKG_LOC     or setmetatable({}, weakk)       -- obj -> path:loc
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

--- Helper for PKG.lua files loading compiled dynamic libraries
M.LIB_EXT = '.so'; if M.UNAME == 'Windows' then M.UNAME = '.dll' end

-- discover() sets this as table[name, dir]
M.PKGS = false

-- These are modified before loading the package.
-- The package can inspect it to (for example) know it's version string,
-- i.e. local version = require'pkglib'.PKG.version
--
-- It is recommended to do this before executing any other `pkg()` calls!
M.PKG  = nil -- PKG.lua being loaded
M.PATH = nil -- path to lua file being loaded

local OKAY = '** pkgrequire okay **'
local function isOkay(msg)
  if string.find(msg, OKAY, 1, true) then return msg end
end
local msgh = function(msg, level)
  if isOkay(msg) then return msg end
  return sfmt('PKG.lua error %s:\n%s',
    msg, debug.traceback('', (level or 1) + 1))
end

M.ENV = {
  UNAME=UNAME,   LIB_EXT=M.LIB_EXT,
  format=string.format,
  insert=table.insert, sort=table.sort, concat=table.concat,
  pairs=pairs,   ipairs=ipairs,
  error=error,   assert=assert,

  -- civ build system shims
  import=function() end,
  nolua=function() error(OKAY) end,
}; M.ENV.__index = M.ENV

--- Compile + Run (load) paths
local loaderr = function(name, path, err)
  error(string.format('loading pkg %s at %s: %s', name, path, err))
end

--- load(path) -> globals
M.load = function(name, path); assert(name and path)
  local env = setmetatable({}, M.ENV)
  local P = {}; env.P = P
  env.name = function(n) P.name = n end
  env.summary = function(s) P.summary = s                   end
  env.pkg = function(p) for k,v in pairs(p) do P[k] = v end; return P end
  env.lua = function(l) for k,v in pairs(l) do P[k] = v end end
  local pkg, err = loadfile(path, nil, env)
  if not pkg then loaderr(name, path, err) end
  local ok, errmsg = xpcall(pkg, msgh)

  if not ok and not isOkay(errmsg) then
    error(sfmt('%s failed with error:\n%s', path, errmsg))
  end
  for k,v in pairs(P) do env[k] = v end
  if P.src then env.srcs = P.src end
  if P.lib then env.libs = P.lib end
  return env
end

--- load the PKG from dir, return it and it's path
M.loadpkg = function(dir, name) --> (PKG, pkgpath)
  local path = pjoin(dir, 'PKG.lua')
  if not pexists(path) then return nil, 'pkg DNE' end
  local pkg = M.load(name or 'PKG', path)
  if pkg.name:find'%.' then
    error("pkg name cannot contain '.': "..pkg.name)
  end
  pkg.PKG_DIR = dir; pkg.dir = dir
  return pkg, path
end

--- load a native library (i.e. so, dll) and return loaded module
M.loadlib = function(name, path) --> mod
  local mod, err = package.loadlib(path, 'luaopen_'..name:gsub('%.', '_'))
  if not mod then loaderr(name, path, err) end
  return mod()
end

-------------------
-- Finding
local function _discover(pkgdir)
  local pkg, pkgpath = M.loadpkg(pkgdir)
  if not pkg then return end
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
M.modules = function(pkgsrcs) --> table[name -> path]
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


--- get pkg's PKG.lua values
M.getpkg = function(pkgname) --> PKG, pkgdir
  if not M.PKGS then M.discover(os.getenv'LUA_PKGS' or '') end
  local pkgdir = M.PKGS[pkgname]; if not pkgdir then return end
  local pkg = M.loadpkg(pkgdir, pkgname)
  return pkg, pkgdir
end

--- get the package. The API is identical to 'require' except
--- it uses LUA_PKGS to search.
M.get = function(name, fallback)
  fallback = (fallback == nil) and M.requireBuiltin or fallback
  local mod = package.loaded[name]; if mod then return mod end
  -- use fallback if pkg doesn't exist
  local pkgname = name:match'(.*)%.' or name
  local pkg, pkgdir = M.getpkg(pkgname)
  if not pkg then
    if fallback then return fallback(name) end
    error(sfmt('name %s (pkgname=%s) not found', name, pkgname))
  end
  -- search in srcs for lua modules
  -- FIXME: remove pkg.srcs
  for mname, mpath in pairs(M.modules(pkg.srcs or {})) do
    if mname == name and type(mpath) == 'string' and mpath:match'%.lua$' then
      package.loaded[mname] = dofile(pjoin(pkgdir, mpath))
      return package.loaded[mname]
    end
  end
  -- search in libs for dynamic libraries
  for mname, mpath in pairs(pkg.libs or {}) do
    if mname == name then
      passert(mpath)
      package.loaded[mname] = M.loadlib(mname, pjoin(pkgdir, mpath))
      return package.loaded[mname]
    end
  end
  error(sfmt('PKG %q found but not sub-module %q', pkgname, name))
end

-----------------------
-- MOD
local CONCRETE_TYPE = {
  ['nil']=true, bool=true, number=true, string=true,
}
local srcloc = function(level)
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  return loc:sub(2)..':'..info.currentline
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
    __name='Mod',
    __call=function(T, name)
      assert(type(name) == 'string', 'must provide name str')
      local m = setmetatable({__name=name}, {
        __name=sfmt('Mod<%s>', name),
        __index=M.mod.__index,
        __newindex=M.mod.__newindex,
      })
      M.mod.save(name, m)
      return m
    end,
  })
end

M.isPkg = function(t)
  return type(t) == 'table' and rawget(t, 'PKG_DIR') and true
end

M.isMod = function(t)
  if type(t) ~= 'table' then return false end
  local mt = getmetatable(t)
  return mt and mt.__name and mt.__name:find'^Mod<'
end

M.G = setmetatable({}, {
  __name='G(init globals)',
  __index    = function(_, k)    return rawget(_G, k)    end,
  __newindex = function(g, k, v) return rawset(_G, k, v) end,
})

local noG = function(_, k)
  error(sfmt(
    'global %s is nil/unset. Initialize with G.%s = non_nil_value', k, k
  ), 2)
end

--- make globals typosafe
M.safeGlobal = function()
  -- define method for explicit access
  rawset(_G, 'G', rawget(_G, 'G') or M.G)
  -- override _G (globals table) to throw error on undefined access
  setmetatable(_G, {__name='_G(globals)', __index=noG, __newindex=noG})
end

--- call pkglib directly to "install" it, making [$require] use [$pkglib.get]
--- and adding [$G] and [$mod] globals.
getmetatable(M).__call = function()
  if require == M.get then return end
  M.safeGlobal()
  G.mod     = G.mod or M.mod
  G.require = M.get
end

getmetatable(M).__newindex = function() error'do not modify pkg' end
return M

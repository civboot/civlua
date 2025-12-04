local mty = require'metaty'

--- Core civ (build system) types and functions.
local M = mty.mod'civ.core'
local G = mty.G
G.MAIN = G.MAIN or M

local shim = require'shim'
local fmt = require'fmt'
local ds = require'ds'
local info = require'ds.log'.info
local dload = require'ds.load'
local pth = require'ds.path'
local ix = require'civix'
local T = require'civtest'

local sfmt = string.format
local getmt, setmt = getmetatable, setmetatable
local push = ds.push

local EMPTY = {}
local MOD_INVALID = '[^%w_.]+' -- lua mod name.

M.DIR = pth.canonical(ds.srcdir() or '')
M.LIB_EXT = '.so'
M.DEFAULT_CONFIG = '.civconfig.lua'
M.HOME_CONFIG = pth.concat{pth.home(), '.config/civ.lua'}
M.DEFAULT_OUT = '.civ/'

-- #####################
-- # Target
-- Creating and processing target objects.

local function validateTargets(tgts)
  assert(mty.ty(tgts) == 'table', 'must pass a list of targets')
  for _, tgt in ipairs(tgts) do
    local ty = mty.ty(tgt)
    fmt.assertf(ty == M.Target, 'must be list of Target: %q', ty)
  end
  return tgts
end

--- A build target, the result of compiling a package.
M.Target = mty'Target' {
  'pkgname: name of package target is in.',
  'name [string]: the name of the target.',
  'src: list of input source files (strings).',
  'dep: list of input Target objects (dependencies).',
 [[out: POD table output segregated by language.[+
     * t: PoD in a k/v table, can be used to configure downstream targets.
     * data: list of raw files.
     * include: header file paths for native code (C/iA).
     * lib: dynamic library files (i.e. libfoo.so)
     * bin: executable binaries
     * lua: lua files
 ] ]],
  'a: arbitrary attributes like test, testonly, etc.',
  'build: lua script (file) on how to build target.',
 [[run {string}: command to run the target. The first value must be the path to
     an executable file relative to the out/ dir (i.e. buildDir, installDir). The
     rest of the paramaters are arguments.
 ]],
}
getmetatable(M.Target).__call = function(T, t)
  if type(t.src) == 'string' then t.src = {t.src} end
  if type(t.dep) == 'string' then t.dep = {t.dep} end
  t.dep = t.dep or {}
  validateTargets(t.dep)
  t.a = t.a or {}
  return mty.construct(T, t)
end
function M.Target:__fmt(f)
  f:styled('api', sfmt('%s.%s', self.pkgname, self.name))
end

--- Represents a pkgname.target parsed from a string
M.TargetName = mty'TargetName' {
  'pkgname [string]',
  'name [string]',
}
function M.TargetName:__tostring()
  return sfmt('%s.%s', self.pkgname, self.tgt)
end
M.TargetName.parse = function(T, str)
  local pn, name = str:match'^([%w_]+:[%w_/]*)%.([%w_]+)$'
  if not pn then error(sfmt('invalid target name: %q', str)) end
  return T{ pkgname=pn, name=name }
end

--- Creating a [$cc{ ... }] Target.
--- This is used by the default sys:cc as well as bootstrap.lua.
M.CC = mty'CC' {
  'lib [string]: output library name.',
  'hdr {string}: input header/s.',
  'src {string}: input src file/s.',
}
function M.CC:target()
  local cc = self
  cc.src = type(cc.src) == 'string' and {cc.src} or cc.src or EMPTY
  cc.hdr = type(cc.hdr) == 'string' and {cc.hdr} or cc.hdr or EMPTY
  assert(#cc.src > 0 or #cc.hdr > 0, 'must provide src or hdr')

  local out = {}
  if cc.lib      then out.lib     = 'lib'..cc.lib..M.LIB_EXT end
  if #cc.hdr > 0 then out.include = cc.hdr                 end
  return M.Target {
    src = cc.src,
    out = out,
    build = M.ccBuild,
  }
end

--- Creating a [$lua { ... }] Target.
--- This is used by the default sys:lua as well as bootstrap.lua.
M.Lua = mty'Lua' {
  'mod {string}: the base modname, i.e. "ds" or "ds.testing"',
  'src {string}',
  'dep {Target}',
  'lib {name: Target}: dynamic library modules.',
}
getmetatable(M.Lua).__call = function(T, t)
  if type(t) == 'string' then t = {mod = t} end
  assert(t.mod or t[1], 'must set mod')
  fmt.assertf(not t.mod:find(MOD_INVALID),
    'mod name must have only characters [%%w_.]: %s', t.mod)
  return mty.construct(T, t)
end
function M.Lua:target()
  local l, mod = self, self.mod
  local t = M.Target {
    src = l.src or {mod..'.lua'},
    dep = l.dep or {},
    build = M.luaBuild,
  }
  if l.lib then
    assert(mty.ty(l.lib) == M.Target, l.lib)
    local expect = 'lib'..mod
    local libo = assert(l.lib.out.lib,
      "lib doesn't export out.lib (is it a cc/iA/etc target?)")
    local lib = libo:match'^(.*)%.%w+$'
    fmt.assertf(expect == lib,
      'library for %s must have name %s but is %s (%s)',
      mod, expect, lib, libo)
    push(t.dep, l.lib)
  end

  local luaOut = {}
  local O = mod:gsub('%.', '/')..'/' -- output dir
  for _, src in ipairs(t.src) do
    -- Get the src file's final mod name
    local smod, ext = src:match'([%w_./]*[%w_]+)(%.%w+)'
    fmt.assertf(ext, 'no .ext found: %s', src)
    local smod = smod:gsub('/', '.') -- i.e. ds.testing
    fmt.assertf(not smod:find(MOD_INVALID),
      'src must have only characters [%%w_./]: %s', src)

    -- strip the mod from the beginnging
    if 1 == smod:find(mod, 1, true) then
      smod = smod:sub(#mod+1):match'^%.?(.*)'
    end
    local out
    if smod == '' then out = O:sub(1,-2)..ext
    else               out = O..smod:gsub('%.', '/')..ext end
    if src == out then push(luaOut, out)
    else               luaOut[src] = out end
  end
  t.out = { lua = luaOut }
  return t
end

M.LuaTest = mty'LuaTest' {
  'src {string}',
  'dep {Target}',
}

-- #####################
-- # Pkg
-- Defining, loading and operating on pkg objects.

--- A loaded civ pkg.
M.Pkg = mty'Pkg' {
  'pkgname',
  'a: table of attributes',
}
function M.Pkg:__newindex(name, tgt)
  assert(type(name) == 'string', 'must use string names')
  assert(mty.ty(tgt) == M.Target,
    'Only Targets can be set to pkg keys. Did you mean to set to P.a?')
  tgt.pkgname = self.pkgname
  tgt.name = name
  return mod.__newindex(self, name, tgt)
end

function M.Pkg:__call(...)
  if mty.callable(self.call) then
    assert(G.BOOTSTRAP) -- we must be in bootstrap mode.
    return self.call(self, ...)
  end
  ds.yeet'TODO: Calling luk targets not yet impl'
end

local ENV = ds.copy(dload.ENV)
ENV.__name = 'civ.ENV'
ENV.Target = M.Target

local PKG_CALLED = '__PKG CALLED__'
local function wasPkgCalled(msg)
  if string.find(msg, PKG_CALLED, 1, true) then return msg end
end

M.RESERVED = {pkg=1, import=1, description=1}

local function isPrepkg(pkg) return getmt(pkg) == nil end
local function imported(pkg)
  if isPrepkg(pkg) then return pkg.import or EMPTY end
  return pkg.a.import
end

--- Initialize load of PKG.lua at path.
M.initpkg = function(path)
  local P, env = {}, {}
  env.name    = function(n) P.name    = n end
  env.summary = function(s) P.summary = s end
  env.import  = function(i) P.import  = i end
  env.pkg = function(p) ds.update(P, p); error(PKG_CALLED) end
  local ok, res = dload(path, env, ENV)
  if ok then error(path..' never called pkg{...}') end
  if not res.msg:find(PKG_CALLED) then error(tostring(res)) end
  P.import = P.import or {}
  for k, v in pairs(P.import) do
    if type(k) ~= 'string' or type(v) ~= 'string' then
      error'import must be map of str -> str'
    end
    fmt.assertf(not M.RESERVED[v], 'import name reserved: %s', v)
  end
  return P
end

-- #####################
-- # Building
-- Building targets

local function pushLibs(cmd, tgt)
  if tgt.out.lib then
    push(cmd, '-l'..assert(tgt.out.lib:match'lib([%w_]+)%'..M.LIB_EXT))
  end
  for _, dep in ipairs(tgt.dep) do pushLibs(cmd, dep) end
end

--- How a cc target is built
--- TODO: move this to a sys/ script.
M.ccBuild = function(ldr, tgt)
  local F = ldr:tgtDir(tgt)
  ix.mkDirs(ldr.cfg.buildDir..'lib')
  ldr:copyOut(tgt, 'include')
  local lib = tgt.out.lib; if lib then
    local cmd = {'cc'}
    for _, src in ipairs(tgt.src) do push(cmd, F..src) end
    -- TODO: needs to come from sys:lua.
    push(cmd, '-llua')

    ds.extend(cmd, {'-fPIC', '-I'..ldr.cfg.buildDir..'include'})
    for _, dep in ipairs(tgt.dep or EMPTY) do pushLibs(cmd, dep) end
    push(cmd, '-shared')
    lib = ldr.cfg.buildDir..'lib/'..lib
    ds.extend(cmd, {'-o', lib})
    ix.sh(cmd)
    T.exists(lib)
  end
end

--- How a lua target is built.
M.luaBuild = function(ldr, tgt)
  ldr:copyOut(tgt, 'lua')
end

-- #####################
-- # Civ
-- The Civ object and it's configuration.

--- The user configuration, typically at ./.civconfig.lua
M.Cfg = mty'Cfg' {
  'path [string]: the path to this config file.',
 [[host_os [string]: the operating system of this computer.'
    Typically equal to civix.OS]],
  'hubs {string: string}: table of hubname -> /absolute/dir/path',
  'buildDir [string]: directory to put build/test files.',
  'installDir [string]: directory to install files to.',
}
M.Cfg.load = function(T, path)
  local ok, t = dload(path or M.DEFAULT_CONFIG, {HOME=pth.home()})
  assert(ok, t)
  t.path = path
  return M.Cfg(t)
end

--- Holds top-level data structures and algorithms for
--- processing civ build graphs (pkgname graphs).
M.Civ = mty'Civ' {
  'cfg [Cfg]: the user config',
  'hubs: table of hub -> dir (cfg.hubs)',
  'pkgs: table of pkgname -> pkg',
  'imports: table of pkgname -> import_pkgnames',
}
getmetatable(M.Civ).__call = function(T, t)
  assert(t.cfg, 'must set cfg')
  t.hubs    = t.cfg.hubs
  t.pkgs    = t.pkgs or {}
  t.imports = t.imports or {}
  return mty.construct(T, t)
end

--- Fix the pkgname
function M.Civ:fixName(pn) --> pkgname
  assert(not pn:find'//+', 'pkgname cannot contain multiple /')
  return fmt.assertf(pn:match'^([%w_]+:[%w_/]-)/?$',
                     'invalid pkgname: %s', pn)
end

function M.Civ:fixNames(pkgnames)
  for i, pkgname in ipairs(pkgnames) do
    pkgnames[i] = self:fixName(pkgname)
  end
end

--- Get pkgname's full directory.
function M.Civ:getDir(pkgname) --> dir/
  local hub, p = pkgname:match'^([%w_]+):([%w_/]*)$'
  if not hub then error('invalid pkgname: '..pkgname) end
  p = pth.concat{self.hubs[hub] or error('unknown hub: '..hub), p}
  return p == '' and p or pth.toDir(p)
end

--- Get target
function M.Civ:target(tgt) --> Target?, errmsg
  if mty.ty(tgt) == M.Target   then return tgt
  elseif type(tgt) == 'string' then
    tgt = M.TargetName:parse(tgt)
  end
  local pkg = self.pkgs[tgt.pkgname]
  if not pkg then return nil, tgt.pkgname..': pkg not found' end
  local t = pkg[tgt.name]; if t then return t end
  return nil, sfmt('%s: target %q not found in pkg', tgt, tgt.name)
end

function M.Civ:targets(tgts) --> {Target}
  local out = {}; for _, t in ipairs(tgts) do
    push(out, assert(self:target(t)))
  end
  return out
end

function M.Civ:tgtDir(tgt)
  return self:getDir(assert(tgt.pkgname))
end

--- Copy output files from [$tgt.out[outKey]].
function M.Civ:copyOut(tgt, outKey)
  if not tgt.out[outKey] then return nil, 'missing out: '..outKey end
  local F, T = self:tgtDir(tgt), self.cfg.buildDir..outKey..'/'
  for from, to in pairs(tgt.out[outKey]) do
    if type(from) == 'number' then from = to end
    to = T..to; fmt.assertf(not ix.exists(to), 'to %q already exists', to)
    from = F..from
    fmt.assertf(ix.exists(from), 'src %q does not exists', from)
    ix.forceCp(from, to)
  end
  return true
end

function M.Civ:preload(pkgname)
  pkgname = self:fixName(pkgname)
  local pkg = self.pkgs[pkgname]; if pkg then return pkg end
  local d = self:getDir(pkgname)
  pkg = M.initpkg(d..'PKG.lua')
  pkg.name = pkgname
  self.pkgs[pkgname] = pkg
  local imports = ds.sort(ds.values(pkg.import or EMPTY))
  assert(imports)
  for i, pn in ipairs(imports) do imports[i] = self:fixName(pn) end
  self.imports[pkgname] = imports
  for _, dep in ipairs(self.imports[pkgname]) do self:preload(dep) end
  pkg.dir = d
  return pkg
end

function M.Civ:loadPkg(prepkg) --> Pkg
  assert(isPrepkg(prepkg))
  local pkgname = assert(prepkg.name)
  local dir = self:getDir(pkgname)
  local env, pkg = {}, M.Pkg{pkgname=pkgname, a=prepkg}
  -- these were stored during preload.
  env.name    = ds.noop -- FIXME: remove
  env.summary, env.import = ds.noop, ds.noop
  env.pkg = function(_)
    env.P, env.pkg, env.name, env.summary, env.import = pkg
    for k, import in pairs(prepkg.import) do
      info('importing %s=%q', k, import)
      env[k] = assert(self.pkgs[import])
    end
    return pkg
  end
  local ok, res = dload(dir..'PKG.lua', env, ENV)
  assert(ok, res)

  self.pkgs[pkgname] = pkg
  return pkg
end

--- Load the pkgs and update self.pkgs with values.
--- Returned the build-ordered list of pkgnames.
function M.Civ:load(pkgnames) --> ordered
  self:fixNames(pkgnames)
  for i, pkgname in ipairs(pkgnames) do self:preload(pkgnames[i]) end
  local ordered, cycle = ds.dagSort(pkgnames, self.imports)
  fmt.assertf(not cycle, 'import cycle detected: %q', cycle)
  for _, pkgname in ipairs(ordered) do
    local pkg = assert(self.pkgs[pkgname])
    if isPrepkg(pkg) then self:loadPkg(pkg) end
  end
  return ordered
end

--- recursively find all deps
local function targetDepMap(tgts, depMap)
  for _, tgt in ipairs(tgts) do
    if not depMap[tgt] then
      info('!! targetDepMap %q', tgt)
      depMap[tgt] = tgt.dep or EMPTY
      targetDepMap(tgt.dep or EMPTY, depMap)
    end
  end
end

--- Build the target.
function M.Civ:build(tgts)
  info('Civ.build: %q', tgts)
  tgts = self:targets(tgts)
  local depMap = {}; targetDepMap(tgts, depMap)
  local ordered, cycle = ds.dagSort(tgts, depMap)
  fmt.assertf(not cycle, 'import cycle detected: %q', cycle)
  for _, tgt in ipairs(ordered) do
    info('building target %q', tgt)
    tgt.build(self, tgt)
  end
end

return M

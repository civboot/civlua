#!/usr/bin/env -S lua
local G = G or _G
local mty = require'metaty'

--- The civ build system.
local M = mty.mod'civ'
G.MAIN = G.MAIN or M

local fmt = require'fmt'
local ds = require'ds'
local dload = require'ds.load'
local pth = require'ds.path'
local ix = require'civix'
local T = require'civtest'

local sfmt = string.format
local getmt, setmt = getmetatable, setmetatable
local push = ds.push

if package.config:sub(1,1) == '\\' then
     M.OS = 'Windows'
else M.OS = select(2, ix.sh'uname') end

local EMPTY = {}
local LIB_EXT = '.so'
local DEFAULT_CONFIG = '.civconfig.lua'
local HOME_CONFIG = pth.concat{pth.home(), '.config/civ.lua'}
local DEFAULT_OUT = '.civ/'
local CONFIG_TMPL = [[
-- holds the config table, returned at end.
local C = {}

-- the host operating system. This primarily affects
-- what build flags are used when compiling C code.
C.host_os = %q

-- A table of hubname -> /absolute/dir/path/
-- This should contain the "software hubs" (which contain HUB.lua files)
-- that you want your project to depend on when being built.
C.hubs = %q

return C -- return for civ to read.
]]

--- civ init arguments.
M.Init = mty'Init' {
  'out [string]: path to output config.lua', out=DEFAULT_CONFIG,
  'base [string]: base config to copy from',
}

--- civ build arguments.
M.Build = mty'Build' {
  'config [string]: path to civ config.', config=DEFAULT_CONFIG,
  'out [string]: path to build outputs.', out=DEFAULT_OUT,
}

--- civ cmdline tool arguments.
M.Args = {
  subcmd = true,
  build = M.Build,
}

--- A build target, the result of compiling a package.
M.Target = mty'Target' {
  'pkgname: name of package target is in.',
  'src: list of input source files (strings).',
  'dep: list of input Target objects (dependencies).',
 [[out: POD table output segregated by language.[+
  * t: PoD in a k/v table, can be used to configure downstream targets.
  * data: list of raw files.
  * hdr: header file paths for native code (C/iA).
  * lib: dynamic library files (i.e. libfoo.so)
  * bin: executable binaries
  * lua: lua files
] ]],
  'a: arbitrary attributes like test, testonly, etc.',
  'build: lua script (file) on how to build target.',
  'run: lua script (file) on how to run target.',
 [[builddep: build-only dependencies, typically used only by library rules
  (i.e. [$cc]).
 ]],
}
getmetatable(M.Target).__call = function(T, t)
  if type(t.src) == 'string' then t.src = {t.src} end
  if type(t.dep) == 'string' then t.dep = {t.dep} end
  t.a = t.a or {}
  return mty.construct(T, t)
end

--- Copy output files from Target.out[outKey].
function M.Target:copyOut(ldr, outKey) --> ok, errmsg
  if not self.out[outKey] then return nil, 'missing out: '..outKey end
  local F, T = ldr:tgtDir(self), ldr.out..outKey..'/'
  for from, to in pairs(self.out[outKey]) do
    if type(from) == 'number' then from = to end
    to = T..to; fmt.assertf(not ix.exists(to), 'to %q already exists', to)
    from = F..from
    fmt.assertf(ix.exists(from), 'src %q does not exists', from)
    ix.forceCp(from, to)
  end
  return true
end

local MOD_INVALID = '[^%w_.]+' -- lua mod name.

--- Attributes for cc{...} target.
M.CC = mty'CC' {
  'lib [string]: output library name.',
  'hdr {string}: input header/s.',
  'src {string}: input src file/s.',
}

local function pushLibs(cmd, tgt)
  if tgt.out.lib then
    push(cmd, '-l'..assert(tgt.out.lib:match'lib([%w_]+)%'..LIB_EXT))
  end
  for _, dep in ipairs(tgt.dep) do pushLibs(cmd, dep) end
end

--- How a cc target is built
--- TODO: move this to a sys/ script.
M.ccBuild = function(ldr, tgt)
  local F = ldr:tgtDir(tgt)
  ix.mkDirs(ldr.out..'lib')
  local lib = tgt.out.lib; if lib then
    local cmd = {'cc'}
    for _, src in ipairs(tgt.src) do push(cmd, F..src) end
    -- TODO: needs to come from sys:lua.
    push(cmd, '-llua')

    ds.extend(cmd, {'-fPIC', '-I'..ldr.out..'hdr'})
    for _, dep in ipairs(tgt.dep or EMPTY) do pushLibs(cmd, dep) end
    push(cmd, '-shared')
    lib = ldr.out..'lib/'..lib
    ds.extend(cmd, {'-o', lib})
    ix.sh(cmd)
    T.exists(lib)
  end
  tgt:copyOut(ldr, 'hdr')
end

--- Target result from cc{...}
M.ccTarget = function(cc)
  cc = M.CC(cc)
  cc.src = type(cc.src) == 'string' and {cc.src} or cc.src or EMPTY
  cc.hdr = type(cc.hdr) == 'string' and {cc.hdr} or cc.hdr or EMPTY
  assert(#cc.src > 0 or #cc.hdr > 0, 'must provide src or hdr')

  local out = {}
  if cc.lib      then out.lib = 'lib'..cc.lib..LIB_EXT end
  if #cc.hdr > 0 then out.hdr = cc.hdr                 end
  return M.Target {
    src = ds.sort(ds.extend(ds.copy(cc.src), cc.hdr)),
    out = out,
    build = M.ccBuild,
  }
end

--- Attributes for lua{...} target.
M.Lua = mty'Lua' {
  'mod {string}: the base modname, i.e. "ds" or "ds.testing"',
  'src {string}',
  'dep {Target}',
  'lib {name: Target}: dynamic library modules.',
}

--- How a lua target is built.
--- TODO: move to sys/ script.
M.luaBuild = function(ldr, tgt)
  tgt:copyOut(ldr, 'lua')
end

--- Target result from lua{...}
M.luaTarget = function(l)
  if type(l) == 'string' then l = {mod = l} end
  l = M.Lua(l)
  local mod = assert(l.mod or l[1], 'must set mod')
  fmt.assertf(not l.mod:find(MOD_INVALID),
    'mod name must have only characters [%%w_.]: %s', l.mod)

  local t = M.Target {
    src = l.src or {mod..'.lua'},
    dep = l.dep or {},
    build = M.luaBuild,
  }
  if l.lib then
    assert(mty.ty(l.lib) == M.Target, l.lib)
    local expect = 'lib'..l.mod
    local lib = assert(l.lib.out.lib,
      "lib doesn't export out.lib (is it a cc/iA/etc target?)")
    local libo = lib:match'^(.*)%.%w+$'
    fmt.assertf(expect == libo,
      'library for %s must have name %s but is %s (%s)',
      mod, expect, libo, lib)
    push(t.dep, lib)
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

--- A loaded civ pkg.
M.Pkg = mty'Pkg' {
  'a: table of attributes',
}
M.Pkg.__newindex = mty.mod.__newindex
getmetatable(M.Pkg).__index = nil

-- TODO: throw error if variable DNE
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

M.Civ = mty'Civ' {
  'out [string]: output directory',
  'hubs: table of hub -> dir',
  'pkgs: table of pkgname -> pkg',
  'imports: table of pkgname -> import_pkgnames',
}
getmetatable(M.Civ).__call = function(T, t)
  assert(t.hubs, 'must set hubs')
  t.out     = pth.toDir(t.out)
  t.pkgs    = t.pkgs or {}
  t.imports = t.imports or {}
  return mty.construct(T, t)
end

--- Fix the pkgName
function M.Civ:fixName(pn)
  assert(not pn:find'//+', 'pkgname cannot contain multiple /')
  return fmt.assertf(pn:match'^([%w_]+:[%w_][%w_/]-)/?$',
                     'invalid pkgname: %s', pn)
end

function M.Civ:fixNames(pkgnames)
  for i, pkgname in ipairs(pkgnames) do
    pkgnames[i] = self:fixName(pkgname)
  end
end

--- Get pkgname's full directory.
function M.Civ:getDir(pkgname) --> dir/
  local hub, p = pkgname:match'^([%w_]+):([%w_/]+)$'
  if not hub then error('invalid pkgname: '..pkgname) end
  p = pth.concat{self.hubs[hub] or error('unknown hub: '..hub), p}
  return p == '' and p or pth.toDir(p)
end

function M.Civ:tgtDir(tgt)
  return self:getDir(assert(tgt.pkgname))
end

function M.Civ:preload(pkgname)
  pkgname = self:fixName(pkgname)
  local pkg = self.pkgs[pkgname]; if pkg then return pkg end
  local d = self:getDir(pkgname)
  pkg = M.initpkg(d..'PKG.lua')
  pkg.name = pkgname
  self.pkgs[pkgname] = pkg
  local imports = ds.sort(ds.values(pkg.import or EMPTY))
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
  local env, pkg = {}, M.Pkg{a=prepkg}
  -- these were stored during preload.
  env.name    = ds.noop -- FIXME: remove
  env.summary, env.import = ds.noop, ds.noop
  env.pkg = function(_)
    env.P, env.pkg, env.name, env.summary, env.import = pkg
    for _, import in ipairs(self.imports[pkg.a.name]) do
      env[import] = self.pkgs[import]
    end
    env.cc  = M.ccTarget
    env.lua = M.luaTarget
    return pkg
  end
  local ok, res = dload(dir..'PKG.lua', env, ENV)
  assert(ok, res)
  for _, tgt in pairs(pkg) do tgt.pkgname = pkgname end

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

--- Build the target.
function M.Civ:build(tgt)
  local ty = mty.ty(tgt)
  fmt.assertf(ty == M.Target, 'can only build civ.Target type: %q', ty)
  for _, dep in ipairs(tgt.dep or EMPTY) do
    self:build(dep)
  end
  tgt.build(self, tgt)
end

function M.Init:__call()
  local cfg
  if G.BOOTSTRAP then
    cfg = self.base and assert(dload(self.base)) and pth.read(self.base)
      or CONFIG_TMPL:format(OS, --[[hubs=]] {
        civ = ds.srcdir(), sys = ds.srcdir()..'sys/'
      })
  else
    cfg = self.base or HOME_CONFIG
    cfg = assert(dload(cfg)) and pth.read(cfg)
  end
  if not pth.exists(HOME_CONFIG) then
    pth.write(HOME_CONFIG, cfg)
    io.fmt:styled('notify', 'Wrote base config to: ')
    io.fmt:styled('path', HOME_CONFIG, '\n')
  end
  pth.write(self.out, cfg)

  io.fmt:styled('notify', 'Wrote config to: ')
  io.fmt:styled('path', self.out, '\n')
  io.fmt:styled('notify', 'Feel free to customize it as-needed.', '\n')
end

function M.Build:__call()
  local c = M.Civ{
    out=self.out,
  }
end

return M

local mty = require'metaty'

--- Core civ (build system) types and functions.
local M = mty.mod'civ.core'
local G = mty.G
G.MAIN = G.MAIN or M

local shim = require'shim'
local fmt = require'fmt'
local ds = require'ds'
local dload = require'ds.load'
local info = require'ds.log'.info
local pth = require'ds.path'
local pod = require'pod'
local luk = require'luk'
local lson = require'lson'
local ix = require'civix'
local File = require'lines.File'
local T = require'civtest'

local sfmt = string.format
local getmt, setmt = getmetatable, setmetatable
local push, pop = ds.push, table.remove

local EMPTY = {}
local MOD_INVALID = '[^%w_.]+' -- lua mod name.

M.DIR = pth.canonical(ds.srcdir() or '')
M.LIB_EXT = '.so'
M.DEFAULT_CONFIG = '.civconfig.lua'
M.HOME_CONFIG = pth.concat{pth.home(), '.config/civ.lua'}
M.DEFAULT_OUT = '.civ/'

M.ENV = ds.copy(luk.ENV)
M.ENV.__index = M.ENV

-- #####################
-- # Target
-- Creating and processing target objects.

local function pkgnameSplit(str) --> hub, pkgpath
  local hub, pkgpath = str:match'^([%w_]+):(.*)'
  if not pkgpath then error(sfmt('invalid pkgname: %q', str)) end
  return hub, pkgpath
end

local function tgtnameSplit(str) --> pkgname, name
  if str:find'#' then
    local pkgname, name = str:match'^([%w_]+:[%w_/]*[%w_]+)#([%w_]*)$'
    if not pkgname then error(sfmt('invalid target name: %q', str)) end
    return pkgname, name
  end
  local hub, pkgpath = pkgnameSplit(str)
  if pkgpath == '' then return hub..':', hub end
  local name = select(2, pth.last(pkgpath))
  fmt.assertf(not name:find'[^%w_]', 'invalid name: %q', str)
  return sfmt('%s:%s', hub, pkgpath), name
end
M.tgtnameSplit = tgtnameSplit

local function tgtnameFix(tgtname)
  local pkgname, name = tgtnameSplit(tgtname)
  return sfmt('%s#%s', pkgname, name)
end

--- Represents a pkgname.target parsed from a string
M.TargetName = mty'TargetName' {
  'pkgname [string]',
  'name [string]',
}
function M.TargetName:__tostring()
  return sfmt('%s#%s', self.pkgname, self.name)
end
M.TargetName.parse = function(T, tgtname)
  local pn, name = tgtnameSplit(tgtname)
  return T{ pkgname=pn, name=name }
end

--- A build target, the result of compiling a package.
M.Target = pod(mty'Target' {
  'pkgname [str]: name of package target is in.',
  'name [str]: the name of the target.',
  'dir [str]: directory of src files',
  'src {key: str}: list of input source files (strings).',
  'dep {str}: list of input Target objects (dependencies).',
  'depIds {int}: list of dependency target ids. Populated for Builder.',
 [[out [table]: POD table output segregated by language.[+
     * t: PoD in a k/v table, can be used to configure downstream targets.
     * data: list of raw files.
     * include: header file paths for native code (C/iA).
     * lib: dynamic library files (i.e. libfoo.so)
     * bin: executable binaries
     * lua: lua files
 ] ]],
  'tag [table]: arbitrary attributes like test, testonly, etc.',
  'build [str]: lua script (file) on how to build target.',
 [[run {string}: command to run the target. The first value must be the path to
     an executable file relative to the out/ dir (i.e. buildDir, installDir). The
     rest of the paramaters are arguments.
 ]],
})
M.ENV.Target = M.Target
getmetatable(M.Target).__call = function(T, t)
  if type(t.src) == 'string' then t.src = {t.src} end
  if type(t.dep) == 'string' then t.dep = {t.dep} end
  t.dep = t.dep or {}
  for i, dep in ipairs(t.dep) do
    t.dep[i] = tgtnameFix(dep)
  end
  t.tag = t.tag or {}
  return mty.construct(T, t)
end
function M.Target:tgtname() 
  return sfmt('%s#%s', self.pkgname, self.name)
end

--- Return a copy of the target with ids used instead of deps.
local function targetWithIds(tgt, ids)
  tgt = ds.copy(tgt)
  tgt.depIds = {}
  for i, dep in ipairs(tgt.dep) do
    tgt.depIds[i] = fmt.assertf(ids[dep], '%q target not found', dep)
  end
  return tgt
end

-- #####################
-- # Civ
-- The Civ object and it's configuration.

M.CfgBuilder = mty'CfgBuilder' {
 [[direct [bool]: prefer building directly
   (running build scripts w/ dofile).
 ]],
}

--- The user configuration, typically at ./.civconfig.lua
M.Cfg = mty'Cfg' {
  'path [string]: the path to this config file.',
 [[host_os [string]: the operating system of this computer.'
    Typically equal to civix.OS]],
  'hubs {string: string}: table of hubname -> /absolute/dir/path',
  'buildDir [string]: directory to put build/test files.',
  'installDir [string]: directory to install files to.',
  'builder [CfgBuilder]: builder settings',
}
M.Cfg.load = function(T, path)
  local ok, t = dload(path or M.DEFAULT_CONFIG, {HOME=pth.home()})
  assert(ok, t)
  t.path = path
  for h, d in pairs(t.hubs) do t.hubs[h] = pth.abs(d) end
  t.builder = M.CfgBuilder(t.builder or {})
  return M.Cfg(t)
end

--- Holds top-level data structures and algorithms for
--- processing civ build graphs (pkgname graphs).
M.Civ = mty'Civ' {
  'cfg [Cfg]: the user config',
  'hubs: table of hub -> dir (cfg.hubs)',
  'pkgs: table of pkgname -> pkg',
  'luk [luk.Luk]',
  'cycle',
  'builder [civ.Builder]: direct builder',
}
getmetatable(M.Civ).__call = function(T, self)
  assert(self.cfg, 'must set cfg')
  self.hubs = self.cfg.hubs
  self.pkgs = self.pkgs or {}
  self.luk  = self.luk or luk.Luk{envMeta=M.ENV}
  self.cycle = self.cycle or {}
  self = mty.construct(T, self)
  self.luk.pathFn = function(p) return self:abspath(p) end
  return self
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

function M.Civ:getPkgname(dep) --> pkgname
  return dep:match'^([%w_]+:[%w_/]*)'
end

--- Given a pkg:path/to/file convert to an abspath (used for Luk).
function M.Civ:abspath(pkgpath) --> abspath
  local hub, p = pkgpath:match'([%w_]+):(.*)'
  if not hub then error(pkgpath..' must start with "hub:"') end
  return pth.concat{self.hubs[hub] or error('unknown hub: '..hub), p}
end

--- Get pkgname's full directory.
function M.Civ:pkgDir(pkgname) --> dir/
  local hub, p = pkgname:match'^([%w_]+):([%w_/]*)$'
  if not hub then error('invalid pkgname: '..pkgname) end
  p = pth.concat{self.hubs[hub] or error('unknown hub: '..hub), p}
  return p == '' and p or pth.toDir(p)
end

function M.Civ:tgtDir(tgt) --> dir/
  return self:pkgDir(assert(tgt.pkgname))
end

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

function M.Civ:loadPkg(pkgname)
  pkgname = assert(self:fixName(pkgname))
  local pkg = self.pkgs[pkgname]; if pkg then return pkg end
  luk.checkCycle(self.cycle, pkgname)
  info('loading pkg %q', pkgname)
  push(self.cycle, pkgname); self.cycle[pkgname] = 1

  local pkgfile = pkgname..'/PKG.lua'
  pkg = self.luk:import(pkgfile)
  fmt.assertf(mty.ty(pkg) == 'table',
    '%q did not return a table', pkgfile)
  pkg.pkgname = pkgname
  for k, tgt in pairs(pkg) do -- validation
    fmt.assertf(type(k) == 'string',
      '%s.%q: must have only string keys', pkgname, k)
    fmt.assertf(not k:find'[^%w_]',
      '%s.%q: keys must be of [%w_]', pkgname, k)
    fmt.assertf(type(tgt) == 'string' or mty.ty(tgt) == M.Target,
      '%s.%s: not a string or Target', pkgname, k)
  end
  for k, tgt in pairs(pkg) do -- load deps
    if mty.ty(tgt) == M.Target then
      tgt.pkgname, tgt.name = pkgname, k
      tgt.dir = self:abspath(pkgname)..'/'
      for _, dep in ipairs(tgt.dep) do
        local dty = mty.ty(dep)
        fmt.assertf(dty == 'string',
          'target %s has invalid dep type %q', tgt:tgtname(), dty)
        local pkgnameDep = self:getPkgname(dep)
        if pkgnameDep ~= pkgname then
          self:loadPkg(pkgnameDep)
        end
      end
    end
  end

  assert(pop(self.cycle) == pkgname); self.cycle[pkgname] = nil
  self.pkgs[pkgname] = pkg
  push(self.pkgs, pkg)
  info('pkg loaded: %q', pkgname)
  return pkg
end

--- Load the pkgs and update self.pkgs with values.
function M.Civ:load(pkgnames)
  for _, pn in ipairs(pkgnames) do self:loadPkg(pn) end
end

--- recursively find all deps
function M.Civ:targetDepMap(tgts, depMap)
  for i, tgtname in ipairs(tgts) do
    fmt.assertf(type(tgtname) == 'string')
    if not depMap[tgtname] then
      local tgt = self:target(tgtname)
      depMap[tgtname] = tgt.dep or EMPTY
      self:targetDepMap(tgt.dep or EMPTY, depMap)
    end
  end
end

--- Build the target.
function M.Civ:build(tgts)
  info('Civ.build: %q', tgts)
  local depMap = {}; self:targetDepMap(tgts, depMap)
  local ordered, cycle = ds.dagSort(tgts, depMap)
  fmt.assertf(not cycle, 'import cycle detected: %q', cycle)
  info('build ordering: %q', ordered)

  -- For creating and running build scripts inline
  local main = G.MAIN
  G.MAIN = nil
  local builder = require'civ.Builder' {
    ids = {}, cfg = self.cfg, targets = {}, tgtsDb = {},
  }:set()

  local ids = {} -- map tgtname -> id
  local tgtsDbPath = self.cfg.buildDir..'targets.json'
  local cfgArg    = '--config='..assert(self.cfg.path)
  local tgtsDbArg = '--tgtsDb='..tgtsDbPath
  local tgtFile = File { path = tgtsDbPath, mode = 'w' }
  info('Civ.build args: %s %s', cfgArg, tgtsDbArg)
  for id, tgtname in ipairs(ordered) do
    local tgt = self:target(tgtname)
    if not tgt.build then goto skip end
    info('building target %q', tgtname)
    tgt = targetWithIds(tgt, ids)
    push(builder.targets, tgt) -- for inline
    tgtFile:write(lson.json(tgt)); tgtFile:write'\n'
    tgtFile:flush()
    ids[tgtname] = id
    local hub, bpath = pkgnameSplit(tgt.build)
    local script = self.hubs[hub]..bpath
    if tgt.tag.builder == 'bootstrap'
        or (tgt.tag.builder == 'direct' and self.cfg.builder.direct) then
      -- build directly in-process: script must have no deps outside of civ.
      ds.clear(builder.ids); builder.ids[1] = id
      info('build direct: %q', script)
      dofile(script); G.MAIN = nil
    else
      -- build in a separate process
      local hub, bpath = pkgnameSplit(tgt.build)
      local cmd = {script, cfgArg, tgtsDbArg, tostring(id)}
      info('build cmd: %q', cmd)
      ix.sh(cmd)
    end
    ::skip::
  end

  builder:close()
  G.MAIN = main
end

return M

#!/usr/bin/env -S lua
local G = G or _G
local mty = require'metaty'

--- The civ build system command.
local M = mty.mod'civ'
G.MAIN = G.MAIN or M

local shim = require'shim'
local ds = require'ds'
local pth = require'ds.path'
local info = require'ds.log'.info
local ix = require'civix'
local core = require'civ.core'

local sfmt = string.format
local push = ds.push

local function tgtnamesSplit(args) --> pkgnames, tgtnames
  local pkgnames, tgtnames = {}, {}
  for _, tgtname in ipairs(args) do
    local tgt = core.TargetName:parse(tgtname)
    push(tgtnames, tostring(tgt))
    if not pkgnames[tgt.pkgname] then
      push(pkgnames, tgt.pkgname)
      pkgnames[tgt.pkgname] = true
    end
  end
  return pkgnames, tgtnames
end

--- civ init arguments.
M.Init = mty'Init' {
  'out [string]: path to output config.lua', out=core.DEFAULT_CONFIG,
  'base [string]: base config to copy from',
}

M.Base = mty'Base' {
  'config [string]: path to civ config.', config=core.DEFAULT_CONFIG,
}

--- Usage: [$civ build hub:tgt#name]
M.Build   = mty.extend(M.Base, 'Build', {})

--- Usage: [$civ test hub:tgt#name]
M.Test   = mty.extend(M.Build, 'Test', {})

--- Usage: [$civ install hub:tgt#name]
M.Install = mty.extend(M.Base, 'Install', {
  "force [bool]: do not confirm deletion of files.",
})

--- civ cmdline tool arguments.
M.Args = {
  subcmd=true,
  init    = M.Init,
  build   = M.Build,
  test    = M.Test,
  install = M.Install,
}

local CONFIG_TMPL = [[
-- holds the config table, returned at end.
local C = {}

-- the host operating system. This primarily affects
-- what build flags are used when compiling C code.
C.host_os = %q

-- A table of hubname -> /absolute/dir/path/
-- This should contain the "software hubs" (which contain HUB.lua files)
-- that you want your project to depend on when being built.
C.hubs = {
  -- This hub, which contains libraries and software for
  -- the civboot tech stack (along with this build tool).
  civ = %q,

  -- The sys hub, which contains system-specific rules for building
  -- source code.
  sys = %q,
}

-- The directory where `civ build` and `civ test` puts files.
C.buildDir = '.civ/'

-- The directory where `civ install` puts files.
C.installDir = HOME..'.local/civ/'

return C -- return for civ to read.
]]

local BASH_ADD = [[
CIV=%s
export PATH=$PATH:$CIV/bin:$CIV/lua
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CIV/lib
export LUA_PATH="$LUA_PATH;$CIV/lua/?.lua"
export LUA_CPATH="$LUA_CPATH;$CIV/lib/lib?.so"
export LUA_SETUP=vt100
]]

function M.Init:__call()
  info('civ init', self)
  local cfg
  if G.BOOTSTRAP then
    cfg = self.base and assert(dload(self.base)) and pth.read(self.base)
       or sfmt(CONFIG_TMPL, ix.OS, core.DIR, core.DIR..'sys/')
  else
    cfg = self.base or core.HOME_CONFIG
    cfg = assert(dload(cfg)) and pth.read(cfg)
  end
  if not ix.exists(core.HOME_CONFIG) then
    pth.write(core.HOME_CONFIG, cfg)
    io.fmt:styled('notify', 'Wrote base config to: ')
    io.fmt:styled('path', core.HOME_CONFIG, '\n')
  end
  pth.write(self.out, cfg)

  io.fmt:styled('notify', 'Local config is at: ')
  io.fmt:styled('path', self.out, '\n')
  io.fmt:styled('notify', 'Feel free to customize it as-needed.', '\n')
end

function M.build(cv, tgtnames)
  assert(cv.cfg.buildDir, 'must set buildDir')
  -- TODO: check timestamps/etc instead of just deleting everything.
  ix.rmRecursive(cv.cfg.buildDir)
  ix.mkDirs(cv.cfg.buildDir)
  local out = cv:build(tgtnames)
  local f = io.fmt
  f:styled('notify', 'targets built', '\n')
  for _, tgtname in ipairs(tgtnames) do
    f:write(sfmt('  %s\n', tgtname))
  end
  return out
end

function M.test(cv, tgtnames)
  local ordered = M.build(cv, tgtnames)
  local ran = cv:test(tgtnames, ordered)
  local f = io.fmt
  f:styled('good', #ran..' tests passed:', '\n')
  for _, tgtname in ipairs(ran) do
    f:write'  '; f:styled('good', tgtname, '\n')
  end
  f:styled('notify', 'civ test: complete', '\n')
end


function M.Build:__call()
  info('build %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  return M.build(cv, cv:expandAll(self))
end

function M.Test:__call()
  info('test %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  return M.test(cv, cv:expandAll(self))
end

function M.Install:__call()
  info('install %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  local tgtnames = cv:expandAll(self)
  local D = cv.cfg.installDir
  assert(D, 'must set config.installDir')
  if not shim.bool(self.force) and ix.exists(D) then
    io.fmt:styled('warn',
      sfmt('This will delete %s - continue (Y/N)?', D), ' ')
    local inp = io.read'l'
    if inp:sub(1,1):lower() ~= 'y' then
      io.fmt:styled('warn', sfmt('replied %q, exiting', inp), '\n')
      return
    end
  end
  io.fmt:styled('notify', 'installing in ')
  io.fmt:styled('path', D, '\n')
  M.build(cv, tgtnames)
  ix.rmRecursive(cv.cfg.installDir)
  ix.cpRecursive(cv.cfg.buildDir, cv.cfg.installDir)
  io.fmt:styled('notify', 'Installed in '); io.fmt:styled('path', D, '\n')
  for _, tgtname in ipairs(tgtnames) do
    io.fmt:write(sfmt('  %s\n', tgtname))
  end
  io.fmt:styled('notify',
    'Add (something like) the following to your ~/.bashrc', '\n')
  local d = pth.toNonDir(D)
  io.fmt:styled('code', BASH_ADD:format(pth.toNonDir(d)), '\n')
end

M.main = function(args)
  assert(not ix.isRoot(), "Do not run this command as root")
  local a = shim.init(M.Args, shim.parse(args))
  assert(io.fmt and io.user)
  io.fmt:styled('notify', 'Running civ '..a.subcmd, '\n')
  return a[a.subcmd]()
end

if MAIN == M then return ds.main(M.main, arg) end
return M

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

local function parseTargetNames(args) --> pkgnames, tgtnames
  local pkgnames, tgtnames = {}, {}
  for _, tgtname in ipairs(args) do
    info('parsing %q', tgtname)
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

--- civ build arguments.
M.Build   = mty.extend(M.Base, 'Build', {})

--- civ install arguments.
M.Install = mty.extend(M.Base, 'Install', {
  "force [bool]: do not confirm deletion of files.",
})

--- civ cmdline tool arguments.
M.Args = {
  subcmd=true,
  init    = M.Init,
  build   = M.Build,
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

local function build(cv, tgts)
  assert(cv.cfg.buildDir, 'must set buildDir')
  ix.rmRecursive(cv.cfg.buildDir)
  ix.mkDirs(cv.cfg.buildDir)
  local pkgnames, tgtnames = parseTargetNames(tgts)
  info('pkgnames: %q', pkgnames)
  info('tgtnames: %q', tgtnames)

  cv:load(pkgnames)
  cv:build(tgtnames)
  return cv
end

function M.Build:__call()
  info('build %q', self)
  build(core.Civ{cfg=core.Cfg:load(self.config)}, self)
end

function M.Install:__call()
  info('install %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
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
  build(cv, self)
  ix.rmRecursive(cv.cfg.installDir)
  ix.cpRecursive(cv.cfg.buildDir, cv.cfg.installDir)
  io.fmt:styled('notify', 'Installed in ')
  io.fmt:styled('path', D, '\n')
end

M.main = function(args)
  assert(not ix.isRoot(), "Do not (yet) run this command as root")
  args = assert(shim.construct(M.Args, shim.parse(args)))
  io.fmt:styled('notify', 'Running civ '..args.subcmd, '\n')
  args[args.subcmd]()
end

if MAIN == M then M.main(arg) end
return M

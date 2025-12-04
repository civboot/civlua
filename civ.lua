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
    push(tgtnames, tgt)
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

--- civ build arguments.
M.Build = mty'Build' {
  'config [string]: path to civ config.', config=core.DEFAULT_CONFIG,
}

--- civ cmdline tool arguments.
M.Args = {
  subcmd = true,
  init  = M.Init,
  build = M.Build,
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
C.installDir = HOME..'.local/'

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

function M.Build:__call()
  info('build %q', self)
  local c = core.Civ{
    cfg=core.Cfg:load(self.config),
  }
  ix.rmRecursive(c.cfg.buildDir)
  local pkgnames, tgtnames = parseTargetNames(self)
  info('pkgnames: %q', pkgnames)
  info('tgtnames: %q', tgtnames)

  c:load(pkgnames)
  c:build(tgtnames)
  ds.yeet'TODO'
end

M.main = function(args)
  args = assert(shim.construct(M.Args, shim.parse(args)))
  io.fmt:styled('notify', 'Running civ '..args.subcmd, '\n')
  args[args.subcmd]()
end

if MAIN == M then M.main(arg) end
return M

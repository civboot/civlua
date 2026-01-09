#!/usr/bin/env -S lua
local shim = require'shim'

--- civ command
local civ = shim.subcmds'civ' {}

local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'
local pth = require'ds.path'
local info = require'ds.log'.info
local ix = require'civix'
local core = require'civ.core'

local G = mty.G
local sfmt = string.format
local push = ds.push
local assertf = fmt.assertf

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


function civ._pre()
  assert(not ix.isRoot(), "Do not run this command as root")
end

civ._Base = shim.cmd'_Base' {
  'config [string]: path to civ config.', config=core.DEFAULT_CONFIG,
}

--- Usage: [$civ init --config=.civconfig.lua][{br}]
--- Initialize the repository. This should be run when starting a new repo.
civ.init = shim.cmd'init' {
  'config [string]: path to config.lua to output', config=core.DEFAULT_CONFIG,
  'base [string]: base config to copy from',
}

--- Usage: [$civ build hub:tgt#name][{br}]
--- Build targets which match the pattern.
civ.build   = mty.extend(civ._Base, 'build', {})

--- Usage: [$civ test hub:tgt#name][{br}]
--- Test targets which match the pattern.
civ.test   = mty.extend(civ.build, 'test', {})

--- Usage: [$civ run hub:tgt#name -- ...args][{br}]
--- Build+run a single build target which has a single bin or link output.
civ.run    = mty.extend(civ.build, 'run', {})

--- Usage: [$civ install hub:tgt#name][{br}]
--- Install targets which match the pattern.
civ.install = mty.extend(civ._Base, 'install', {
  "force [bool]: do not confirm deletion of files.",
})

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

function civ.init:__call()
  civ._pre()
  info('civ init', self)
  local cfg
  if G.BOOTSTRAP then
    cfg = self.base and assert(dload(self.base)) and pth.read(self.base)
       or sfmt(CONFIG_TMPL, ix.OS, core.DIR, core.DIR..'sys/')
  else
    cfg = self.base or core.HOME_CONFIG
    cfg = assert(require'ds.load'(cfg)) and pth.read(cfg)
  end
  if not ix.exists(core.HOME_CONFIG) then
    pth.write(core.HOME_CONFIG, cfg)
    io.fmt:styled('notify', 'Wrote base config to: ')
    io.fmt:styled('path', core.HOME_CONFIG, '\n')
  end
  pth.write(self.config, cfg)

  io.fmt:styled('notify', 'Local config is at: ')
  io.fmt:styled('path', self.config, '\n')
  io.fmt:styled('notify', 'Feel free to customize it as-needed.', '\n')
end

function civ._build(cv, tgtnames)
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

function civ._test(cv, tgtnames)
  local ordered = civ._build(cv, tgtnames)
  local ran = cv:test(tgtnames, ordered)
  local f = io.fmt
  f:styled('good', #ran..' tests passed:', '\n')
  for _, tgtname in ipairs(ran) do
    f:write'  '; f:styled('good', tgtname, '\n')
  end
  f:styled('notify', 'civ test: complete', '\n')
end


function civ.build:__call()
  civ._pre()
  info('build %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  return civ._build(cv, cv:expandAll(self))
end

function civ.test:__call()
  civ._pre()
  info('test %q', self)
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  return civ._test(cv, cv:expandAll(self))
end

function civ.run:__call()
  civ._pre()
  info('run %q', self)
  local cmd = shim.popRaw(self)
  assert(#self == 1, 'usage: civ run hub:tgtname')
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  local tgtnames = cv:expandAll(self)
  assertf(#tgtnames == 1, 'must run a single target, expanded to: %q',
         tgtnames)
  local tgt = cv:target(tgtnames[1])
  local bin = tgt.out.bin
  if not bin then bin = tgt.link end
  assertf(bin and ds.pairlen(bin) == 1,
    '%s must have exatly one bin/ output: %q', tgtnames[1], tgt.out)
  bin = select(2, next(bin))
  assertf(bin:match'^bin/', '%s is not in bin/', bin)

  civ._build(cv, tgtnames)
  table.insert(cmd, 1, cv.cfg.buildDir..bin)
  info('running: %q', cmd)
  cmd.ENV = cv.ENV
  return ix.sh(cmd)
end

function civ.install:__call()
  civ._pre()
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
  civ._build(cv, tgtnames)
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

if shim.isMain(civ) then return os.exit(civ:main(arg)) end
return civ

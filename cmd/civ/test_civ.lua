
local T = require'civtest'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local luk = require'luk'
local civ = require'civ'
local core = require'civ.core'

local D = pth.resolve(ds.srcdir()..'../..')
local O = D..'.out/civ/'

local HUBS = { civ = D, sys = D..'sys/' }

local CFG_PATH = O..'civconfig.lua'

local CFG = ([[
return {
  buildDir = %q,
  hubs = {
    civ = %q, sys = %q,
  },
}
]]):format(O, D, D..'sys/')

local function newCiv()
  ix.rmRecursive(O); ix.mkDirs(O)
  pth.write(CFG_PATH, CFG)
  return core.Civ{cfg=core.Cfg:load(CFG_PATH)}
end

local LUA_BUILD = "sys:lua/build.lua"

local METATY_PKG = core.Target {
  pkgname="civ:lib/metaty", name="metaty",
  dir = pth.abs(D.."lib/metaty/"),
  src={"metaty.lua"},
  out={lua={"metaty.lua"}},
  api={'metaty'},
  tag={builder='bootstrap'},
  kind='build', run=LUA_BUILD,
}

local FMT_PKG = core.Target {
  pkgname='civ:lib/fmt', name='fmt',
  dir = pth.abs(D.."lib/fmt/"),
  src={ 'fmt.lua', 'binary.lua' },
  dep={'civ:lib/metaty#metaty'},
  out={lua={
    'fmt.lua',
    ['binary.lua'] = 'fmt/binary.lua',
  }},
  api={'fmt', 'fmt.binary'},
  tag={builder='bootstrap'},
  kind='build', run=LUA_BUILD,
}

T.tgtname = function()
  T.eq({'foo:bar',  'baz'}, {core.tgtnameSplit'foo:bar#baz'})
  T.eq({'foo:bar',  'bar'}, {core.tgtnameSplit'foo:bar'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:#foo'})
  T.eq({'foo:',     'foo'}, {core.tgtnameSplit'foo:'})
end

T.loadPkg = function()
  local c = newCiv()

  local metatyPkg = c:loadPkg'civ:lib/metaty'
  T.eq(luk.Table{
    pkgname="civ:lib/metaty",
    summary="Simple but effective Lua type system.",
    metaty=METATY_PKG,
  }, metatyPkg)

  local fmtPkg = c:loadPkg'civ:lib/fmt'
  T.eq(FMT_PKG, fmtPkg.fmt)
end

local fd_out = {
  lua = { 'fd.lua', }
}
local libfd_out = {
  include = { 'fd.h' },
  lib     = 'libfd.so',
}

T.loadFd = function()
  local l = newCiv()
  l:loadPkgs{'civ:lib/fd'}
  T.eq(METATY_PKG.out, l.pkgs['civ:lib/metaty'].metaty.out)
  local fdpkg = l.pkgs['civ:lib/fd']
  T.eq(fd_out,    fdpkg.fd.out)
  T.eq({'fd.c'},  fdpkg.libfd.src)
  T.eq(libfd_out, fdpkg.libfd.out)
end

T.loadLinesTesting = function()
  local l = newCiv()
  l:loadPkgs{'civ:lib/lines/testing'}
  T.eq({
    lua = { ['testing.lua'] = 'lines/testing.lua' },
  }, l.pkgs['civ:lib/lines/testing'].testing.out)
end

T.expand = function()
  local l = newCiv()
  T.eq({"civ:lib/metaty#metaty"},             l:expand'civ:lib/metaty#.*')
  T.eq({"civ:lib/ds#ds", "civ:lib/ds#dslib"}, l:expand'civ:lib/ds#')
  T.eq({
    "civ:lib/ds#ds", "civ:lib/ds#dslib",
    "civ:lib/ds/testing#testing",
  }, l:expand'civ:lib/ds/.*#')
  T.eq({"civ:lib/ds#ds"}, l:expand'civ:lib/ds')
  T.eq({"civ:lib/ds#ds"}, l:expand'civ:lib/ds#ds')
end

T.buildMetaty = function()
  local l = newCiv()
  l:loadPkgs{'civ:lib/metaty'}
  l:build{'civ:lib/metaty'}
  T.path('.out/civ/', {
    ['lua/'] = {
      ['metaty.lua'] = io.open'lib/metaty/metaty.lua',
    }
  })
end

T.buildDs = function()
  local l = newCiv()
  l:loadPkgs{'civ:lib/ds'}
  local dsPkg = l.pkgs['civ:lib/ds']
  T.eq({"civ:lib/metaty#metaty", "civ:lib/fmt#fmt", "civ:lib/ds#dslib"},
       dsPkg.ds.dep)
  T.eq(core.Target{
    pkgname="civ:lib/ds",
    name="dslib",
    dir="/home/rett/projects/civstack/lib/ds/",
    src={"ds.c"},
    dep={},
    out={
      include={"ds.h"},
      lib="libds.so"
    },
    tag={ builder = 'bootstrap' },
    kind='build', run="sys:cc/build.lua",
  }, dsPkg.dslib)

  l:build{'civ:lib/ds'}

  T.path('.out/civ/include', {
    ['ds.h'] = io.open'lib/ds/ds.h',
  })
  T.exists'.out/civ/lib/libds.so'
end

T.buildCiv = function()
  local l = newCiv()
  l:loadPkgs{'civ:cmd/civ'}
  l:build{'civ:cmd/civ'}
end

T.testMetaty = function()
  local l = newCiv()
  local p = 'civ:lib/tests'
  local t = p..'#test_metaty'
  l:loadPkgs{p}
  l:test({t}, l:build{t})
end

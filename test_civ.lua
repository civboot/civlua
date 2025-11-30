
local T = require'civtest'
local ds = require'ds'

local civ = require'civ'
local ix = require'civix'

local D = ds.srcdir() or ''
local O = '.out/civ/'

local METATY_PKG = {
  doc="README.cxt",
  homepage="https://lua.civboot.org#Package_metaty",
  import={},
  license="UNLICENSE",
  name="metaty",
  summary="Simple but effective Lua type system using metatables",
  url="git+http://github.com/civboot/civlua",
  version="0.1-15"
}

T.init = function()
  local metaty_init = civ.initpkg(D..'lib/metaty/PKG.lua')
  T.eq(METATY_PKG, metaty_init)

  local fmt_init = civ.initpkg(D..'lib/fmt/PKG.lua')
  T.eq(fmt_init.import, {metaty = 'civ:lib/metaty'})
end

local HUBS = { civ = D }

local function newCiv()
  ix.rmRecursive(O); ix.mkDirs(O)
  return civ.Civ{out = O, hubs=HUBS}
end

local metaty_out = {
  lua = { 'metaty.lua' },
}
local fmt_out = {
  lua = {
    'fmt.lua',
    ['binary.lua'] = 'fmt/binary.lua',
  },
}
local fd_out = {
  lua = {
    'fd.lua',
    'fd/IFile.lua',
  }
}
local libfd_out = {
  hdr = { 'fd.h' },
  lib = 'libfd.so',
}

T.loadMetaty = function()
  local l = newCiv()
  l:load{'civ:lib/metaty/'}
  T.eq(metaty_out, l.pkgs['civ:lib/metaty'].metaty.out)
end

T.loadFmt = function()
  local l = newCiv()
  l:load{'civ:lib/fmt'}
  T.eq(metaty_out, l.pkgs['civ:lib/metaty'].metaty.out)
  T.eq(fmt_out, l.pkgs['civ:lib/fmt'].fmt.out)

end

T.loadFd = function()
  local l = newCiv()
  l:load{'civ:lib/fd'}
  T.eq(metaty_out, l.pkgs['civ:lib/metaty'].metaty.out)
  local fdpkg = l.pkgs['civ:lib/fd']
  T.eq(fd_out,    fdpkg.fd.out)
  T.eq({'fd.c', 'fd.h'}, fdpkg.libfd.src)
  T.eq(libfd_out, fdpkg.libfd.out)

end

T.buildMetaty = function()
  local l = newCiv()
  l:load{'civ:lib/metaty'}
  l:build(l.pkgs['civ:lib/metaty'].metaty)
  T.path('.out/civ/', {
    ['lua/'] = {
      ['metaty.lua'] = io.open'lib/metaty/metaty.lua',
    }
  })

end

T.buildFd = function()
  local l = newCiv()
  l:load{'civ:lib/fd'}
  local fdpkg = l.pkgs['civ:lib/fd']
  l:build(fdpkg.libfd)

  T.path('.out/civ/hdr', {
    ['fd.h'] = io.open'lib/fd/fd.h',
  })
  T.exists'.out/civ/lib/libfd.so'

end

ds.yeet'ok'

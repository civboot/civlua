name    = 'civ'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
doc     = 'README.cxt'
repo    = 'https://github.com/civboot/civlua'
homepage = 'https://lua.civboot.org'
srcs = { 'civ.lua' }
pkgs = {
  -- Core
  'lib/shim',
  'lib/metaty',
  'lib/fmt',
  'lib/civtest',
  'lib/ds',
  'lib/civdb',
  'lib/lines',
  'lib/lap',
  'lib/fd',
  'lib/civix',
  'lib/lson',
  'lib/pegl',

  -- pretty colors
  'lib/asciicolor',
  'lib/vt100',

  -- data storage / vcs
  'lib/smol',
  'lib/tv',
  'lib/vcds',
  'lib/luck',

  -- TODO: refactor into other libs
  'lib/rebuf',

  -- cmd
  'cmd/cxt',
  'cmd/doc',
  'cmd/ff',
  'cmd/pkgrock',
  'cmd/ele',
}

local FILE = 'https://github.com/civboot/civlua/blob/main/'
local FILE_LINE = FILE..'%s#L%s'
local RENDERED = 'https://html-preview.github.io/'
               ..'?url=https://github.com/civboot/civlua/main/'
local EXT_PAT = '%.(%w+)$'
local USE_RENDERED = {html='html', cxt='html'}

html = {
  pathUrl = function(p)
    if USE_RENDERED[p:match(EXT_PAT)] then return p:gsub(EXT_PAT, USE_RENDERED) end
    if p:match':(%d+)$' then
      return FILE_LINE:format(p:match'^(.*):(%d+)$')
    end
    return FILE..p
  end,
}

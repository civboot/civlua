name    = 'civ'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
srcs = { 'civ.lua' }
pkgs = {
  -- Core
  'lib/shim',
  'lib/metaty',
  'lib/fmt',
  'lib/civtest',
  'lib/ds',
  'lib/lines',
  'lib/lap',
  'lib/fd',

  -- libs
  'lib/asciicolor',
  'lib/vt100',
  'lib/lson',
  'lib/tv',
  'lib/vcds',
  'lib/pegl',
  'lib/luck',
  'lib/rebuf',
  'lib/civix',
  'lib/patience',

  -- cmd
  'cmd/cxt', -- lib + cmd
  'cmd/doc', -- lib + cmd
  'cmd/ff',
  'cmd/pkgrock',
  'cmd/ele',
}

local FILE = 'https://github.com/civboot/civlua/blob/main/'
local FILE_LINE = FILE..'%s#L%s'
local RENDERED = 'https://htmlpreview.github.io/'
               ..'?https://github.com/civboot/civlua/main/'
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

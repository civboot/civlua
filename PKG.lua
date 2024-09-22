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

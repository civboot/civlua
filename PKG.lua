name    = 'civ'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
srcs = { 'civ.lua' }
pkgs = {
  'lib/shim',
  'lib/metaty',
  'lib/civtest',
  'lib/doc',
  'lib/ds',
  'lib/lines',
  'lib/lson',
  'lib/tv',
  'lib/lap',
  'lib/vcds',
  'lib/fd',
  'lib/asciicolor',
  'lib/vt100',
  'lib/civix',
  'lib/pegl',
  'lib/luck',
  'lib/patience',
  'lib/rebuf',

  'cmd/cxt',
  'cmd/ele',
  'cmd/ff',
  'cmd/pkgrock',

  'experiment/tso',
}

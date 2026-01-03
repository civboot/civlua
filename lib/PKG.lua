local P = {}

-- The entire civ:lib.
-- Most civ:cmd commands just include the whole thing for convinience.
P.lib = Target {
  dep = {
    'civ:lib/acsyntax',
    'civ:lib/asciicolor',
    'civ:lib/civix',
    'civ:lib/civtest',
    'civ:lib/ds',
    'civ:lib/fd',
    'civ:lib/fmt',
    'civ:lib/lap',
    'civ:lib/lines',
    'civ:lib/lson',
    'civ:lib/luk',
    'civ:lib/metaty',
    'civ:lib/pegl',
    'civ:lib/pod',
    'civ:lib/shim',
    'civ:lib/vcds',
    'civ:lib/vt100',
  },
}

P.testing = Target {
  dep = {
    'civ:lib',
    'civ:lib/ds/testing',
    'civ:lib/lines/testing',
    'civ:lib/pod/testing',
  },
}

return P

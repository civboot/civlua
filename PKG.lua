local P = {}

--- target to install full civstack.
P.full = Target {
  dep = {
    'civ:cmd/civ',
    'civ:cmd/ff',
  }
}

return P


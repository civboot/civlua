import {
  metaty = 'civ:lib/metaty'
  civtest = 'civ:lib/civtest'
}

P.test = civtest {
  src = { 'test.lua' },
  dep = { metaty.metaty },
}

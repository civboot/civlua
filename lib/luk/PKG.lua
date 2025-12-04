summary"luk: lua config language."
import {
  lua    = 'sys:lua',
  ds     = 'civ:lib/ds',
}
pkg { name = 'luk' }

P.luk = lua {
  mod = 'luk',
  dep = {
    ds.ds,
  },
}

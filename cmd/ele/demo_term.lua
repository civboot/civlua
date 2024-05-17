local mty = require'metaty'
local x = require'civix'
local et = require'ele.testing'

et.SLEEP = 0.01

-- direct demo
et.runterm(function(T)
  T:clear()
  et.diagonal(T)
  local left = 'set:'
  et.setleft(T, left)
  et.setcolgrid(T, #left + 1)
  mty.print'... wrote to stdout'
  x.sleep(et.SLEEP * 20)
  mty.eprint'... wrote to stderr'
end)

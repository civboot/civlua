local mty = require'metaty'
local x = require'civix'
local et = require'ele.testing'
local Buffer = require'rebuf.buffer'.Buffer
local Edit   = require'ele.edit'.Edit

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

-- -- demo edit
-- et.runterm(function(T)
--   local ft = require'civix.term'.FakeTerm(100, 100)
-- 
--   T:clear()
--   et.diagonal(ft)
--   local e = Edit(nil, Buffer.new(mty.tostring(ft)))
--   for tl=1,T.h do
--     e:draw(T); T:flush(); x.sleep(et.SLEEP)
--     e.l, e.c = tl, e.c + 4
--     e:insert'< INSERTED >'
--   end
-- 
-- end)

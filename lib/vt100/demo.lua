local vtt = require'vt100.testing'
local cx = require'civix'

local demobox = function(t, l, c)
  t.l, t.c = l, c
  local hort = ('-'):rep(11)
  local vert = '+\n'..('|\n'):rep(3)..'+'
  t.text:insert(l, c, 'this\n  is a\ndemo\n')
  t.text:insert(l - 1, c - 3,         hort)
  t.text:insert(l + 3, c - 3,         hort)
  t.text:insert(l - 1, c - 3,         vert)
  t.text:insert(l - 1, c + #hort - 3, vert)
end
-- direct demo
vtt.run(function(t)
  demobox(t, 2, 5)
  demobox(t, 9, 9)
  t:draw()
  cx.sleep(0.5)
  t.l, t.c = 14, 1; t:draw()
  cx.sleep(0.1)
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

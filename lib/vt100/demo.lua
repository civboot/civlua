local ds = require'ds'
local cx = require'civix'
local vtt = require'vt100.testing'

local pause = tonumber(os.getenv'SHOWTIME') or 0.1

local demobox = function(t, l, c)
  t.l, t.c = l, c
  local hort = ('-'):rep(11)
  local hfg  = ('g'):rep(11)
  local hbg  = ('d'):rep(11)

  local vert = '+\n'..('|\n'):rep(3)..'+'
  local vbg  = ('d\n'):rep(#vert)

  t.text:insert(l, c, 'this\n  is a\ndemo\n')
  t.fg  :insert(l, c, 'Mwlz\n  dz  \nCgrd\n')
  t.text:insert(l - 1, c - 3,         hort)
  t.fg  :insert(l - 1, c - 3,         hfg)
  t.bg  :insert(l - 1, c - 3,         hbg)

  t.text:insert(l + 3, c - 3,         hort)
  t.fg  :insert(l + 3, c - 3,         hfg)
  t.bg  :insert(l + 3, c - 3,         hbg)

  t.text:insert(l - 1, c - 3,         vert)
  t.bg  :insert(l - 1, c - 3,         vbg)

  t.text:insert(l - 1, c + #hort - 3, vert)
  t.bg  :insert(l - 1, c + #hort - 3, vbg)
end

-- direct demo
vtt.run(function(t)
  demobox(t, 2, 5)
  demobox(t, 9, 9)
  t:draw()
  cx.sleep(pause)
  t.l, t.c = 14, 1; t:draw()
  cx.sleep(pause / 2)
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

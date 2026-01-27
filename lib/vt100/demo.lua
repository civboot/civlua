local G = G or _G
assert(not G.MAIN, 'this script must be main')
G.MAIN = {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local cx = require'civix'
local vtt = require'vt100.testing'

local pause = tonumber(os.getenv'SHOWTIME') or 0.1

local function demobox(t, l, c)
  t.l, t.c = l, c
  local tw, th = 6, 3 -- text width, height
  local txt = 'this\n  is a\ndemo\n'
  local tfg = 'MWLZ\n  dz  \nCgrd\n'

  local hort = ('-'):rep(tw+2)
  local hfg  = ('g'):rep(tw+2)
  local hbg  = ('d'):rep(tw+2)

  local vert = '+\n'..('|\n'):rep(3)..'+'
  local vbg  = ('d\n'):rep(5)

  t.text:insert(l, c, txt)
  t.fg  :insert(l, c, tfg)

  -- top
  t.text:insert(l - 1, c - 1,         hort)
  t.fg  :insert(l - 1, c - 1,         hfg)
  t.bg  :insert(l - 1, c - 1,         hbg)

  -- bot
  t.text:insert(l + th, c - 1,         hort)
  t.fg  :insert(l + th, c - 1,         hfg)
  t.bg  :insert(l + th, c - 1,         hbg)

  -- left
  t.text:insert(l - 1, c - 1,         vert)
  t.bg  :insert(l - 1, c - 1,         vbg)

  -- right
  t.text:insert(l - 1, c + tw, vert)
  t.bg  :insert(l - 1, c + tw, vbg)
end

-- direct demo
vtt.run(function(t)
  demobox(t, 2, 5)
  demobox(t, 9, 9)
  log.info('Drawing TXT:\n%s', fmt(t))
  log.info('Drawing FG:\n%s', fmt(t.fg))
  log.info('Drawing BG:\n%s', fmt(t.bg))
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
--   local e = Edit(nil, Buffer.new(fmt(ft)))
--   for tl=1,T.h do
--     e:draw(T); T:flush(); x.sleep(et.SLEEP)
--     e.l, e.c = tl, e.c + 4
--     e:insert'< INSERTED >'
--   end
-- 
-- end)

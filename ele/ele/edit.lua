-- #####################
-- # Edit struct
local ds = require'ds'
local gap = require'ele.gap'
local T = require'ele.types'
local motion = require'ele.motion'
local Edit, CursorChange = T.Edit, T.CursorChange

local add = table.insert

local M = {}

-- Implements an edit view and state
Edit.new=function(container, buf)
  return Edit{
    id=T.nextViewId(),
    buf=buf,
    l=1, c=1, vl=1, vc=1,
    th=-1, tw=-1,
    tl=-1, tc=-1,
    container=container,
    canvas=nil,
  }
end
Edit.__tostring=function(e)
  return string.format('Edit[id=%s]', e.id)
end
Edit.copy=function(e)
  return ds.copy(e, {id=T.nextViewId()})
end
Edit.close=function(e)
  assert(not e.container, "Edit not removed before close")
end
Edit.forceHeight=function(e) return e.fh end
Edit.forceWidth=function(e)  return e.fw end
Edit.offset=function(e, off)
  return e.buf.gap:offset(off, e.l, e.c)
end
Edit.curLine= function(e) return e.buf.gap:get(e.l) end
Edit.colEnd=function(e) return #e:curLine() + 1 end
Edit.lastLine=function(e) return e.buf.gap:get(e:len()) end
-- bound the column for the line
Edit.boundCol= function(e, c, l)
  return ds.bound(c, 1, #e.buf.gap:get(l or e.l) + 1)
end

-- update view to see cursor (if needed)
Edit.viewCursor=function(e)
  -- if e.l > e:len() then e.l = e:len() end
  if e.l > e:len() then error(
    ('e.l OOB: %s > %s'):format(e.l, e:len())
  )end
  local l, c = e.l, e.c
  l = ds.bound(l, 1, e:len()); c = e:boundCol(c, l)
  if e.vl > l            then e.vl = l end
  if l < e.vl            then e.vl = l end
  if l > e.vl + e.th - 1 then e.vl = l - e.th + 1 end
  if c < e.vc            then e.vc = c end
  if c > e.vc + e.tw - 1 then e.vc = c - e.tw + 1 end
end

-----------------
-- Helpers
Edit.trailWs=function(e, msg)
  local g = e.buf.gap
  while g:get(#g - 1)    ~= ''
        or g:get(#g - 2) ~= '' do
    e:append('')
  end
end

Edit.len = function(e) return e.buf:len() end

-----------------
-- Mutations: these update the changes in the buffer
Edit.changeStart=function(e) e.buf:changeStart(e.l, e.c) end

Edit.changeUpdate2=function(e)
  local ch = assert(e.buf:getStart())
  ch.l2, ch.c2 = e.l, e.c
end
Edit.append=function(e, msg)
  local l2 = e:len() + 1
  e.buf:append(msg)
  e.l, e.c = l2, 1
  e:changeUpdate2()
end

Edit.insert=function(e, s)
  local ch = e.buf:insert(s, e.l, e.c);
  e.l, e.c = e.buf.gap:offset(#s, e.l, e.c)
  -- if causes cursor to move to next line, move to end of cur line
  -- except in specific circumstances
  if (e.l > 1) and (e.c == 1) and ('\n' ~= s:sub(#s)) then
    e.l, e.c = e.l - 1, #e.buf.gap:get(e.l - 1) + 1
  end
  e:changeUpdate2()
end

Edit.remove=function(e, ...)
  local l1, c1 = e.l, e.c
  local l, c, l2, c2 = gap.lcs(...)
  local g, ch = e.buf.gap
  local len = #g
  l, l2 = ds.bound(l, 1, len), ds.bound(l2, 1, len)
  if not c then -- only lines specified
    l, l2 = ds.sort2(l, l2); assert(not c2)
    if e.l <= l2 then
      e.l = ds.bound(e.l - (l2 - l), 1, len - (l2 - l1))
    end
    c, c2 = 1, #g:get(l2) + 1
  else
    l, c = g:bound(l, c);  l2, c2 = g:bound(l2, c2)
    if motion.lcGe(e.l, e.c, l2, c2) then
      local off = g:offsetOf(e.l, e.c, l2, c2)
      e.l, e.c = g:offset(off, e.l, e.c)
    end
  end
  ch = e.buf:remove(l, c, l2, c2)
  e:changeUpdate2()
end

Edit.removeOff=function(e, off, l, c)
  if off == 0 then return end
  l, c = l or e.l, c or e.c;
  local l2, c2 = e.buf.gap:offset(ds.decAbs(off), l, c)
  if off < 0 then l, l2, c, c2 = l2, l, c2, c end
  e:remove(l, c, l2, c2)
end

Edit.replace=function(e, s, ...)
  local l1, c1 = e.l, e.c
  local l, c = gap.lcs(...)
  assert(e.l == l and (not c or c1 == c))
  local chR = e:remove(...);
  local chI = e:insert(s)  ;
  e.l, e.c = l1, c1
  e:changeUpdate2()
end

-----------------
-- Undo / Redo
Edit.undo=function(e)
  local chs = e.buf:undo(); if not chs then return end
  local c = assert(chs[1])
  e.l, e.c = c.l1, c.c1
end
Edit.redo=function(e)
  local chs = e.buf:redo(); if not chs then return end
  local c = assert(chs[1])
  e.l, e.c = c.l2, c.c2
end

-----------------
-- Draw to terminal
Edit.draw=function(e, term, isRight)
  assert(term); e:viewCursor()
  e.canvas = {}
  -- assert(e.fh == 0 or e.fh == e.th)
  -- assert(e.fw == 0 or e.fw == e.tw)
  for i, line in ipairs(e.buf.gap:sub(e.vl, e.vl + e.th - 1)) do
    add(e.canvas, string.sub(line, e.vc, e.vc + e.tw - 1))
  end
  while #e.canvas < e.th do add(e.canvas, '') end
  local l = e.tl
  for _, line in ipairs(e.canvas) do
    local c = e.tc
    for char in line:gmatch'.' do
      term:set(l, c, char)
      c = c + 1
    end
    local fill = e.tw - #line
    if fill > 0 then
      if isRight then term:cleareol(l, c)
      else for _=1, fill do
        term:set(l, c, ' '); c = c + 1
      end end
    end
    l = l + 1
  end
end

-- Called by model for only the focused editor
Edit.drawCursor=function(e, term)
  e:viewCursor()
  local c = ds.min(e.c, #e:curLine() + 1)
  term:golc(e.tl + (e.l - e.vl), e.tc + (c - e.vc))
end

return M

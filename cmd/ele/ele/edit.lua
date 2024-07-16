local M = mod'ele.edit'

-- #####################
-- # Edit struct
local mty    = require'metaty'
local ds     = require'ds'
local log    = require'ds.log'
local motion = require'rebuf.motion'
local types = require'ele.types'
local lines = require'lines'

local push = table.insert
local span, lsub = lines.span, lines.sub

INT_ID = INT_ID or 1

M.Edit = mty'Edit' {
  'id[int]',
  'container', -- parent (Window/Model)
  'canvas',
  'buf[Buffer]',
  -- override specific keybindings for this buffer
  'modes [table]',
  'l[int]',  l=1,     'c[int]',  c=1,   -- cursor line, col
  'vl[int]', vl=1,    'vc[int]', vc=1,  -- view   line, col (top-left)
  'tl[int]', tl=-1,   'tc[int]', tc=-1, -- term   line, col (top-left)
  'th[int]', th=-1,   'tw[int]', tw=-1, -- term   height, width
  'fh[int]', fh=0,    'fw[int]', fw=0,  -- force h,w
}

getmetatable(M.Edit).__call = function(T, container, buf)
  return mty.construct(T, {
    id=types.uniqueId(), container=container, buf=assert(buf),
  })
end

M.Edit.close = function(e)
  assert(not e.container, "Edit not removed before close")
end
M.Edit.__len       = function(e) return #e.buf end
M.Edit.__tostring  = function(e) return string.format('Edit[id=%s]', e.id) end
M.Edit.copy        = function(e) return ds.copy(e, {id=T.nextViewId()}) end
M.Edit.forceHeight = function(e) return e.fh end
M.Edit.forceWidth  = function(e) return e.fw end
M.Edit.curLine     = function(e)
  log.info('!! l=%s len=%s', e.l, #e.buf.dat)
  return e.buf.dat[e.l] end
M.Edit.colEnd      = function(e) return #e:curLine() + 1 end
M.Edit.lastLine    = function(e) return e.buf[#e] end
M.Edit.offset = function(e, off)
  return lines.offset(e.buf.dat, off, e.l, e.c)
end

-- bound the column for the line
M.Edit.boundCol= function(e, c, l)
  return ds.bound(c, 1, #e.buf[l or e.l] + 1)
end

-- update view to see cursor (if needed)
M.Edit.viewCursor = function(e)
  if e.l > #e then error(
    ('e.l OOB: %s > %s'):format(e.l, #e)
  )end
  local l, c = e.l, e.c
  l = ds.bound(l, 1, #e); c = e:boundCol(c, l)
  if e.vl > l            then e.vl = l end
  if l < e.vl            then e.vl = l end
  if l > e.vl + e.th - 1 then e.vl = l - e.th + 1 end
  if c < e.vc            then e.vc = c end
  if c > e.vc + e.tw - 1 then e.vc = c - e.tw + 1 end
end

-----------------
-- Mutations: these update the changes in the buffer
M.Edit.changeStart = function(e) e.buf:changeStart(e.l, e.c) end

M.Edit.changeUpdate2 = function(e)
  local ch = assert(e.buf:getStart())
  ch.l2, ch.c2 = e.l, e.c
end
M.Edit.append = function(e, msg)
  local l2 = #e + 1
  e.buf:append(msg)
  e.l, e.c = l2, 1
  e:changeUpdate2()
end

M.Edit.insert = function(e, s)
  e.buf:insert(s, e.l, e.c);
  e.l, e.c = lines.offset(e.buf.dat, #s, e.l, e.c)
  -- if causes cursor to move to next line, move to end of cur line
  -- except in specific circumstances
  if (e.l > 1) and (e.c == 1) and ('\n' ~= s:sub(#s)) then
    e.l, e.c = e.l - 1, #e.buf[e.l - 1] + 1
  end
  e:changeUpdate2()
end

M.Edit.remove = function(e, ...)
  local ch = e.buf:remove(...)
  e:changeUpdate2()
end

M.Edit.removeOff = function(e, off, l, c)
  if off == 0 then return end
  l, c = l or e.l, c or e.c;
  local l2, c2 = lines.offset(e.buf.dat, ds.decAbs(off), l, c)
  if off < 0 then l, l2, c, c2 = l2, l, c2, c end
  e:remove(l, c, l2, c2)
end

M.Edit.replace = function(e, s, ...)
  local l1, c1 = e.l, e.c
  local l, c = span(...)
  assert(e.l == l and (not c or c1 == c))
  local chR = e:remove(...);
  local chI = e:insert(s)  ;
  e.l, e.c = l1, c1
  e:changeUpdate2()
end

-----------------
-- Undo / Redo
M.Edit.undo = function(e)
  local chs = e.buf:undo(); if not chs then return end
  local c = assert(chs[1])
  e.l, e.c = c.l1, c.c1
end
M.Edit.redo = function(e)
  local chs = e.buf:redo(); if not chs then return end
  local c = assert(chs[1])
  e.l, e.c = c.l2, c.c2
end

-----------------
-- Draw to terminal
M.Edit.draw = function(e, term, isRight)
  assert(term); e:viewCursor()
  e.canvas = {}
  -- assert(e.fh == 0 or e.fh == e.th)
  -- assert(e.fw == 0 or e.fw == e.tw)
  for i, line in ipairs(lsub(e.buf.dat, e.vl, e.vl + e.th - 1)) do
    push(e.canvas, string.sub(line, e.vc, e.vc + e.tw - 1))
  end
  while #e.canvas < e.th do push(e.canvas, '') end
  for l, line in ipairs(e.canvas) do
    l = e.tl + l - 1
    log.trace('draw tl=%s l=%s', e.tl, l)
    if isRight then term:cleareol(l, e.tc)
    else line = line..string.rep(' ', e.tw - #line) end
    term:golc(l, e.tc)
    term:write(line)
  end
end

-- Called by model for only the focused editor
M.Edit.drawCursor = function(e, term)
  e:viewCursor()
  local c = ds.min(e.c, e:colEnd())
  term:golc(e.tl + (e.l - e.vl), e.tc + (c - e.vc))
end

return M

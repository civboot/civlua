local M = mod'ele.edit'

-- #####################
-- # Edit struct
local mty    = require'metaty'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local motion = require'lines.motion'
local ix = require'civix'
local lines = require'lines'
local Gap   = require'lines.Gap'
local types = require'ele.types'

local push, concat = table.insert, table.concat
local sfmt, srep = string.format, string.rep
local min, max = math.min, math.max
local span, lsub = lines.span, lines.sub

M.Edit = mty'Edit' {
  'id[int]',
  'container', -- parent (Editor/Split)
  'buf[Buffer]',
  'l[int]',  l=1,     'c[int]',  c=1,   -- cursor line, col
  'vl[int]', vl=1,    'vc[int]', vc=1,  -- view   line, col (top-left)
  'tl[int]', tl=-1,   'tc[int]', tc=-1, -- term   line, col (top-left)
  'th[int]', th=-1,   'tw[int]', tw=-1, -- term   height, width
  'fh[int]', fh=0,    'fw[int]', fw=0,  -- force h,w
  'closed [bool]', closed = false,

  -- override specific keybindings for this buffer
  'modes [table]',
  'drawBars [fn[Edit] -> botHeight,leftWidth]',
  'lineStyle [str]: asciicolor style',
    lineStyle = 'bar:line',
}


getmetatable(M.Edit).__call = function(T, t)
  local b = assert(t.buf, 'must set buf')
  t.l, t.c = t.l or b.l, t.c or b.c
  t.id = types.uniqueId()
  local e = mty.construct(T, t)
  e:changeStart()
  return e
end

M.Edit.close = function(e, ed)
  assert(not e.container, "Edit not removed before close")
  e.closed = true
  if e.buf.tmp then
    e.buf.tmp[e] = nil; if #e.buf.tmp == 0 then
      ed.buffers[e.id] = nil
    end
  end
end

M.Edit.save = function(e, ed)
  local b = e.buf; local dat = b.dat
  local ro = b.readonly; b.readonly = true
  local path = assert(dat.path, 'must set path')
  local tpath = path..'.__ELE__'
  -- TODO: schedule the rest as coroutine to not block.
  dat:flush()
  local tmp = assert(io.open(tpath, 'w'))
  dat:dumpf(tmp); tmp:flush()
  dat:close();    tmp:close()
  -- TODO: I should move with :move (need to implement)
  ix.mv(tpath, path)
  b.readonly = ro -- in case the below fails
  dat = assert(ed.newDat(path),
               'CRITICAL: failed to load saved path')
  b.readonly = ro
  b.dat = dat
end

M.Edit.__len       = function(e) return #e.buf end
M.Edit.__tostring  = function(e) return string.format('Edit[id=%s]', e.id) end
M.Edit.copy        = function(e) return ds.copy(e, {id=T.nextViewId()}) end
M.Edit.forceHeight = function(e) return e.fh end
M.Edit.forceWidth  = function(e) return e.fw end
M.Edit.curLine     = function(e)
  return e.buf.dat[e.l] end
M.Edit.colEnd      = function(e) return #e:curLine() + 1 end
M.Edit.lastLine    = function(e) return e.buf[#e] end
M.Edit.offset = function(e, off)
  return lines.offset(e.buf.dat, off, e.l, e.c)
end

M.Edit.boundC = function(e, l,c)
  return ds.bound(c, 1, #e.buf:get(l) + 1)
end
M.Edit.boundLC = function(e, l, c)
  if l <= 1 then
    if #e == 0 then return 1, 1 end
    return 1, ds.bound(c, 1, #e.buf:get(1) + 1)
  end
  l = ds.bound(l, 1, #e)
  return l, e:boundC(l,c)
end

-- bound the column for the line
M.Edit.boundCol= function(e, c, l)
  return ds.bound(c, 1, #e.buf:get(l or e.l) + 1)
end

-- update view fields to see cursor (if needed)
M.Edit.viewCursor = function(e)
  if e.l > 1 and e.l > #e then error(
    ('e.l OOB: %s > %s'):format(e.l, #e)
  )end
  local l, c = e:boundLC(e.l, e.c)
  local bh, bw = e:barDims()
  local th, tw = e.th - bh, e.tw - bw
  if e.vl > l          then e.vl = l end
  if l > e.vl + th - 1 then e.vl = l - th + 1 end
  if c < e.vc          then e.vc = c end
  if c > e.vc + tw - 1 then e.vc = c - tw + 1 end
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
  local b = e.buf
  b:insert(s, e.l, e.c);
  e.l, e.c = lines.offset(b.dat, #s, e.l, e.c)
  -- if causes cursor to move to next line, move to end of cur line
  -- except in specific circumstances
  if (e.l > 1) and (e.c == 1) and ('\n' ~= s:sub(#s)) then
    e.l, e.c = e.l - 1, #b[e.l - 1] + 1
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

--- Clear the buffer.
M.Edit.clear = function(e)
  e:remove(1,#e)
  e.l,e.c = 1,1
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
-- Draw to display
M.Edit.draw = function(e, d, isRight)
  local bh, bw = e:barDims()
  e:viewCursor()
  e:drawBars(d)
  e.th = e.th - bh
  e.tw = e.tw - bw
  e.tc = e.tc + bw
  local b = lines.box(e.buf.dat,
    e.vl,            e.vc,
    e.vl + e.th - 1, e.vc + e.tw - 1)
  d.text:insert(e.tl, e.tc, b)
end

M.Edit.barDims = function(e)
  if e.tw <= 10 or e.th <= 3 then return 0, 0 end
  return 1, 2
end
local pad2 = function(i)
  i = tostring(i)
  return srep(' ', 2 - #i)..i
end
M.Edit.drawBars = function(e, d) --> botHeight, leftWidth
  if e.tw <= 10 or e.th <= 3 then return end
  local tl, tc, th, tw = e.tl, e.tc, e.th, e.tw
  local cl, cc, len = e.l,e.c, #e -- cl,cc: cursor line,col
  local wl = tl  -- wl: write line
  local txt, fgd, bgd = d.text, d.fg, d.bg
  local fb = d.styler:getFB(e.lineStyle)
  local fg,bg = srep(fb:sub(1,1), 2), srep(fb:sub(-1), 2)
  for l=e.vl, e.vl+e.th - 2 do
    if     l <= cl  then txt:insert(wl, tc, pad2(cl - l))
    elseif l <= len then txt:insert(wl, tc, pad2(l - cl))
    else                 txt:insert(wl, tc, '  ') end
    fgd:insert(wl, tc, fg)
    bgd:insert(wl, tc, bg)
    wl = wl + 1
  end

  local id, info = assert(e.buf.id)
  local p = e.buf.dat.path; if p then
    info = sfmt('| %s:%i.%i (b#%i)', pth.nice(p), e.l, e.c, id)
  else info = sfmt('| b#%i %i.%i', id, e.l, e.c) end
  info = info:sub(1, e.tw - 1)..' '
  txt:insert(wl, tc, info)
  for c=tc+#info, tc+tw-1 do txt[wl][c] = '=' end
  return 1, 2
end

-- Called by model for only the focused editor
M.Edit.drawCursor = function(e, t)
  local c = math.min(e.c, e:colEnd())
  t.l, t.c = e.tl + (e.l - e.vl), e.tc + (c - e.vc)
end

M.Edit.copy = function(e)
  e.tl,e.tc, e.tw,e.th = -1,-1, -1,-1
  local e2 = ds.copy(e)
  e2.id, e2.container = types.uniqueId(), nil
  e2.modes = e.modes and ds.copy(e.modes) or nil
  return e2
end

--- Split the edit by wrapping it and a copy into split type S.
--- Return the resulting split.
M.Edit.split = function(e, S) --> split
  local c = e.container
  local sp = S{};  c:replace(e, sp)
  sp:insert(1, e); sp:insert(2, e:copy())
  return sp
end

M.Edit.path = function(e) --> path?
  return e.buf.dat.path
end

return M

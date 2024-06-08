-- Actions builtin plugin
local M = mod and mod'ele.actions' or {}
local motion = require'rebuf.motion'

----------------------------------
-- MOVE
-- This defines the move action
local DOMOVE = {
  lines    = function(e, _, ev) e.l = e.l + ev.lines end,
  sol      = function(e, line) e.c = line:find'%S' or 1                end,
  eol      = function(e, line) e.c = #line                             end,
  forword  = function(e, line)
    e.c = motion.forword(line, e.c) or (e.c + 1)
  end,
  backword = function(e, line)
    e.c = motion.backword(line, e.c) or (e.c + 1)
  end,
  find = function(e, line, ev)
    e.c = line:find(ev.find, e.c, true) or e.c
  end,
  findback = function(e, line, ev)
    e.c = motion.findBack(line, ev.findback, e.c, true) or e.c
  end,
}
local domove = function(e, ev)
  local fn = ev.move and DOMOVE[ev.move]
  if fn      then fn(e, e.buf[e.l], ev) end
  if ev.cols then e.c = e.c + ev.cols   end
  if ev.off  then e:offset(ev.off)      end
end

-- move action
--
-- set move key to one of:
--   lines: move set number of lines (set lines = +/- int)
--   forword, backword: go to next/prev word
--   sol, eol: go to start/end of line
--   find, findback: find character forwards/backwards (set find/findback key)
--
-- these can additionally be set and will be done in order:
--   cols, off: move cursor by columns/offset (positive or negative)
--
-- Supports: times
M.move = function(data, ev, evsend)
  local e = data.edit
  for _=1,ev.times or 1 do domove(e, ev) end
  e.l = math.min(#e.buf, e.l); e.c = e:boundCol(e.c)
end

return M

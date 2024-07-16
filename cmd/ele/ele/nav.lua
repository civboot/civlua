-- nav: core navigation
local M = mod and mod'ele.nav' or {}

local ds = require'ds'
local lap = require'lap'
local cx = require'civix'
local lines = require'lines'

local B = require'ele.bindings'

local dp = ds.dotpath

local isDir = function(p) return p:sub(-1) == '/' end

M.to = mod and mod'ele.nav.to' or {}

M.modes = mod and mod'ele.nav.modes' or {}
M.modes.insert  = { fallback=function() error'cannot insert in nav list' end }
M.modes.command = {
  enter = B.Event{action='nav', 'line'},
  esc   = B.close,
}

-- Create a new buffer for nav related actions
M.navEdit = function(ed) --> new temporary nav buffer
  local b = ed:buffer(); local e = ed:focus(b); push(b.tmp, e)
  e.modes = M.modes
  return e
end

M.to.listcwd = function(ed, ev, evsend)
  local e = M.navEdit(ed)
  local d = function() evsend{action='redraw'} end
  lap:schedule(function()
    cx.walk({assert(CWD)}, {
      dir     = function(p) e:append(p..'/\n'); d() end,
      default = function(p) e:append(p..'\n');  d() end,
    }, 1)
  end)
end

M.to.line = function(ed, ev) ed:focus(ed:buffer(ed.edit:curLine())) end

M.install = function(ed)
  ed.ext.nav = ds.merge(ed.ext.nav or {}, M.to)
end

return M

-- defines ele.Ed

local mty    = require'metaty'
local ds     = require'ds'
local path   = require'ds.path'
local log    = require'ds.log'
local Gap    = require'lines.Gap'
local Buffer = require'rebuf.buffer'.Buffer
local Edit = require'ele.edit'.Edit
local push, pop, concat = table.insert, table.remove, table.concat

-- Ed is the global editor state that actions have access to.
--
-- action signature: function(data, event, evsend)
local Ed = mty'Ed' {
  'mode  [string]: current editor mode',
  'modes [table]: keyboard bindings per mode (see: bindings.lua)',
  'actions [table]: actions which events can trigger (see: actions.lua)',
  'resources [table]: resources to close when shutting down',
  'buffers [List]: list of Buffer objects',
  'edit [Buffer]: the current edit buffer',
  'view [RootView]: the root view',
  'display [Term|other]: display/terminal to write+paint text',
  'run [boolean]: set to false to stop the app', run=true,
  'ext [table]: table for extensions to store data',

  'error [callable]: error handler (ds.log.logfmt sig)',
  'warn  [callable]: warn handler',
  'newDat [callable(text)]: function to create new buffer',
  newDat = function(f) return f and Gap:load(f) or Gap{path=f} end,
  'redraw [boolean]: set to true to force a redraw',
}

Ed.init = function(T, t)
  t = ds.merge({
    mode='command', modes={},
    actions=ds.copy(require'ele.actions'),
    buffers={},
    resources={},
    ext={},
    redraw = true,
  }, t or {})
  require'ele.bindings'.install(t)
  require'ele.nav'.install(t)
  return Ed(t)
end

-- create new buffer from v (path or table of lines)
-- if v is nil the buffer will be an empty tmp buffer
--
-- If v is a string this will first check if a buffer exists at the path.
Ed.buffer = function(ed, v) --> Buffer
  if type(v) == 'string' then
    v = path.abs(v)
    for _, b in pairs(ed.buffers) do
      if v == b.dat.path then return b end
    end
  end
  local id = #ed.buffers + 1
  if type(f) == 'string' then log.info('opening file: %s', f) end
  ed.buffers[id] = Buffer{
    id=id, dat=ed.newDat(v), tmp=not v and {} or nil
  }
  return ed.buffers[id]
end

-- enter focus mode on a single edit view
Ed.focus = function(ed, e)
  if type(e) == 'number' then -- buffer index
    e = ed.buffers[e] or error('invalid buffer index: '..e)
  end
  if mty.ty(e) == Buffer then e = Edit(ed, e)
  else assert(mty.ty(e) == Edit) end
  if ed.view then
    ed.view.container = nil; ed.view:close(ed)
  end
  ed.edit, ed.view = e, e
  return e
end

-- open path and focus. If already open then use existing buffer.
Ed.open = function(ed, path) --> edit
  return ed:focus(ed:buffer(path))
end

Ed.draw = function(ed)
  local v, d, e = ed.view, ed.display, ed.edit
  v.tl, v.tc, v.th, v.tw = 1, 1, d.h, d.w
  v:draw(d)
  e:viewCursor()
  d.l, d.c = e.l, e.c
end

return Ed

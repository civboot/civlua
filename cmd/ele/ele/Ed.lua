-- defines ele.Ed

local mty    = require'metaty'
local ds     = require'ds'
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
  'newbuffer [callable(text)]: function to create new buffer',
    newDat = Gap.read,
}

Ed.init = function(T, t)
  t = ds.merge({
    mode='command', modes={},
    actions=ds.copy(require'ele.actions'),
    buffers={},
    resources={},
    ext={},
  }, t or {})
  require'ele.bindings'.install(t)
  return Ed(t)
end

-- create new buffer from v (path or table of lines)
Ed.buffer = function(ed, v) --> Buffer, index
  local b = Buffer{dat=ed.newDat(v)}
  local i = #ed.buffers + 1; ed.buffers[i] = b
  return b, i
end

-- enter focus mode on a single edit view
Ed.focus = function(ed, e)
  if type(e) == 'number' then -- buffer index
    e = ed.buffers[e] or error('invalid buffer index: '..e)
  end
  if mty.ty(e) == Buffer then e = Edit(ed, e)
  else assert(mty.ty(e) == Edit) end
  ed.edit, ed.view = e, e
  return e
end

Ed.draw = function(ed)
  local v, d = ed.view, ed.display
  v.tl, v.tc, v.th, v.tw = 1, 1, d.h, d.w
  v:draw(d, true)
end

return Ed

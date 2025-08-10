-- defines ele.Editor
local mty    = require'metaty'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local Gap    = require'lines.Gap'
local Buffer = require'lines.buffer'.Buffer
local Edit   = require'ele.edit'.Edit
local et     = require'ele.types'
local push, pop, concat = table.insert, table.remove, table.concat

-- Editor is the global editor state that actions have access to.
--
-- action signature: function(data, event, evsend)
local Editor = mty'Editor' {
  'mode  [string]: current editor mode',
  'modes [table]: keyboard bindings per mode (see: bindings.lua)',
  'actions [table]: actions which events can trigger (see: actions.lua)',
  'resources [table]: resources to close when shutting down',
  'buffers [list[Buffer]]', 'namedBuffers [map[string,Buffer]]',
  'edit [Buffer]: the current edit buffer',
  'view [RootView]: the root view',
  'display [Term|other]: display/terminal to write+paint text',
  'run [boolean]: set to false to stop the app', run=true,
  'ext [table]: table for extensions to store data',

  'error [callable]: error handler (ds.log.logfmt sig)',
  'warn  [callable]: warn handler',
  'newDat [callable(text)]: function to create new buffer',
  newDat = function(f) return f and Gap:load(f) or Gap({}, f) end,
  'redraw [boolean]: set to true to force a redraw',
}

getmetatable(Editor).__call = function(T, t)
  t = ds.merge({
    mode='command', modes={},
    actions=ds.copy(require'ele.actions'),
    buffers={}, namedBuffers=ds.WeakV{},
    resources={},
    ext={},
    redraw = true,
  }, t)
  return mty.construct(T, t)
end

Editor.__fmt = function(ed, f)
  f:write'Editor{mode='; f:string(ed.mode); f:write'}'
end

--- list of named buffers (name -> buffer)

Editor.init = function(ed)
  require'ele.bindings'.install(ed)
  return ed
end

--- Get an existing buffer if it exists
Editor.getBuffer = function(ed, v) --> Buffer?
  if type(v) == 'number' then
    local b = ed.buffers[v]; if b then return b end
  end
  if type(v) == 'string' then
    local id = v:match'b#(%d+)'; if id then
      return ed.buffers[tonumber(id) or ed.BUFFER[id]]
    end

    v = pth.abs(pth.resolve(v))
    for _, b in pairs(ed.buffers) do
      if v == b.dat.path then return b end
    end
  end
end

-- create new buffer from v (path or table of lines)
-- if v is nil the buffer will be an empty tmp buffer
--
-- If v is a string this will first check if a buffer exists at the path.
Editor.buffer = function(ed, v) --> Buffer
  local b = ed:getBuffer(v); if b then return b end
  log.info('creating buffer %q', v)
  local id = #ed.buffers + 1
  ed.buffers[id] = Buffer{
    id=id, dat=ed.newDat(v), tmp=not v and {} or nil
  }
  return ed.buffers[id]
end

-- enter focus mode on a single edit view
Editor.focus = function(ed, e)
  if type(e) == 'number' then -- buffer index
    e = ed.buffers[e] or error('invalid buffer index: '..e)
  end
  if mty.ty(e) == Buffer then e = Edit(ed, e)
  else assert(mty.ty(e) == Edit) end
  assert(not ed.view, 'TODO')
  ed.edit = e
  return e
end

-- open path and focus. If already open then use existing buffer.
Editor.open = function(ed, path) --> edit
  return ed:focus(ed:buffer(path))
end

Editor.draw = function(ed)
  local v, d, e = ed.view or ed.edit, ed.display, ed.edit
  v.tl, v.tc, v.th, v.tw = 1, 1, d.h, d.w
  v:draw(d)
  e:viewCursor()
  d.l, d.c = e.l, e.c
end

Editor.handleStandard = function(ed, ev)
  if ev.mode then
    local err = et.checkMode(ed, ev.mode); if err then
      return ed.error('%s has invalid mode', ev, ev.mode)
    end
    log.info(' + mode %s -> %s', ed.mode, ev.mode)
    ed.mode = ev.mode
  end
end

return Editor

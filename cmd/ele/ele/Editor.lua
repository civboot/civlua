-- defines ele.Editor
local mty    = require'metaty'
local fmt    = require'fmt'
local ds     = require'ds'
local pth    = require'ds.path'
local log    = require'ds.log'
local Gap    = require'lines.Gap'
local Buffer = require'lines.buffer'.Buffer
local Edit   = require'ele.edit'.Edit
local et     = require'ele.types'
local push, pop, concat = table.insert, table.remove, table.concat

local assertf = fmt.assertf
local sfmt = string.format

-- Editor is the global editor state that actions have access to.
--
-- action signature: function(data, event, evsend)
local Editor = mty'Editor' {
  'mode  [string]: current editor mode',
  'modes [table]: keyboard bindings per mode (see: bindings.lua)',
  'actions [table]: actions which events can trigger (see: actions.lua)',
  'resources [table]: resources to close when shutting down',
  'buffers [list[Buffer]]', 'bufferId[map[Buffer, id]]',
  'namedBuffers [map[string,Buffer]]',
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
    buffers={}, bufferId={},
    namedBuffers=ds.WeakV{},
    resources={}, ext={},
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

--- Get an existing buffer if it exists.
--- Else return false if the buffer is path-like and should be
--- created, else nil.
Editor.getBuffer = function(ed, v) --> Buffer?
  if mty.ty(v) == Buffer then
    assert(ed.bufferId[v], 'must create buffer with Editor:buffer')
    return v
  end
  if type(v) == 'number' then
    local b = ed.buffers[v]; if b then return b end
  elseif type(v) == 'string' then
    log.info('!! match', {v:match'b#([%w_-]+)'})
    local id = v:match'b#([%w_-]+)'; if id then
      log.info('!! id %q', id, ed.namedBuffers[id])
      return ed.buffers[tonumber(id) or ed.namedBuffers[id]]
    end

    v = pth.abs(pth.resolve(v))
    for _, b in pairs(ed.buffers) do
      if v == b.dat.path then return b end
    end
  elseif type(v) == 'nil' then -- create buffer
  else error('Cannot convert '..type(v)..' to buffer') end
end

-- create new buffer from v (path or table of lines)
-- idOrPath can be a buffer id, b#123 string or path/to/file.txt.
-- It will look for an existing buffer first, then create a
-- new one if not.
Editor.buffer = function(ed, idOrPath) --> Buffer
  if idOrPath ~= nil then
    local b = ed:getBuffer(idOrPath); if b then return b end
  end
  log.info('creating buffer %q', idOrPath)
  local dat = ed.newDat(idOrPath) -- do first to allow yield
  local id = #ed.buffers + 1
  local b = Buffer{id=id, dat=dat, tmp=not idOrPath and {} or nil}
  ed.buffers[id] = b
  ed.bufferId[b] = id
  return ed.buffers[id]
end

--- Get or create a named buffer (NOT a path).
Editor.namedBuffer = function(ed, name, path)
  local id = ed.namedBuffers[name]
  if id then return ed.buffers[id] end
  local b = ed:buffer(path)
  ed.namedBuffers[name] = assert(b.id)
  return b
end


-- open path and focus. If already open then use existing buffer.
Editor.open = function(ed, path) --> edit
  return ed:focus(ed:buffer(path))
end

Editor.draw = function(ed)
  local v, d, e = ed.view, ed.display, ed.edit
  d.text:insert(1,1, sfmt('[mode:%s]', ed.mode))
  v.tl, v.tc, v.th, v.tw = 2, 1, d.h-1, d.w
  v:draw(d, true)
  e:drawCursor(d)
end

--- Handle standard event fields.
--- Currently this only handles the [$mode] field.
Editor.handleStandard = function(ed, ev)
  local m = ev.mode; if m then
    local err = et.checkMode(ed, m); if err then
      return ed.error('%s has invalid mode', ev, m)
    end
    if ed.mode ~= m then
      log.info(' + mode %s -> %s', ed.mode, m)
      if m == 'insert' and not ed.edit.buf:changed() then
        ed.edit:changeStart()
      elseif ed.mode == 'insert' then
        ed.edit.buf:discardUnusedStart()
      end
      ed.mode = m
    end
  end
end

--- Replace the view/edit from with to.
--- Since Editor supports only [$ed.view] this means
--- it must be that value.
Editor.replace = function(ed, from, to) --> from
  assert(to)
  assert(ed.view == from, 'view being replaced is not ed.view')
  assert(from.container == ed)
  assert(not to.container)
  ed.view = to
  to.container, from.container = ed, nil
  return from
end

--- Remove a view and remove self as it's container.
--- This does NOT close the view.
Editor.remove = function(ed, v) --> v
  assert(ed.view == v, 'view being removed is not ed.view')
  assert(v.container == ed)
  ed.view = nil
  if ed.edit == v then ed.edit = nil end
  v.container = nil
  return v
end

--- Focus the first edit view in container c (default ed.view)
Editor.focusFirst = function(ed, c)
  c = c or ed.view
  while mty.ty(c) ~= Edit do c = c[1] end
  assert(mty.ty(c) == Edit)
  ed.edit = c
  if not ed.view then ed.view = c end
end

--- Replace the current edit view with the new [$ed:buffer(b)].
--- Return the new edit view being focused.
Editor.focus = function(ed, b) --> Edit
  local b = assertf(ed:buffer(b), '%q', b)
  local e = Edit{buf=b}
  if ed.edit then ed.edit.container:replace(ed.edit, e)
  else            e.container = ed end
  ed.edit = e
  if not ed.view then ed.view = e end
  return e
end

return Editor

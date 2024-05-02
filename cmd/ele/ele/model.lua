-- #####################
-- # Model struct
-- Implements the core app

local pkg = require'pkglib'
local mty = pkg'metaty'
local ds = pkg'ds'
local civix = pkg'civix'
local gap  = pkg'rebuf.gap'
local buffer = pkg'rebuf.buffer'

local T = pkg'ele.types'
local action = pkg'ele.action'
local edit = pkg'ele.edit'
local bindings = pkg'ele.bindings'
local data = pkg'ele.data'
local window = pkg'ele.window'

local yld = coroutine.yield
local concat = table.concat
local pnt, ty = mty.print, mty.ty

local M = {}

local DRAW_PERIOD = ds.Duration(0.03)
local MODE = { command='command', insert='insert' }
local Actions = action.Actions
local Model, Edit, Buffer, Bindings = T.Model, T.Edit, buffer.Buffer, T.Bindings

Model.__tostring=function(m)
  return string.format('Model[%s %s.%w]', m.mode, m.h, m.w)
end
Model.new=function(term_, inputCo)
  local mdl = {
    mode='command',
    h=-1, w=-1,
    buffers={}, freeBufId=1, freeBufIds={},
    start=ds.Epoch(0), lastDraw=ds.Epoch(0),
    bindings=Bindings.default(),

    inputCo=inputCo, term=term_,
    events=ds.LL{},
  }
  mdl = setmetatable(mdl, Model)
  mdl.statusEdit = mdl:newEdit('status')
  mdl.searchEdit = mdl:newEdit('search')
  return mdl
end
-- Call after term is setup
Model.init=function(m)
  m.h, m.w = m.term:size()
  m:draw()
end

-- #####################
-- # Status
Model.showStatus=function(self)
  local s = self.statusEdit
  if s.container then return end
  window.windowAdd(self.view, s, 'h', false)
  s.fh, s.fw = 1, nil
end
Model.showSearch=function(self)
  local s = self.searchEdit; if s.container then return end
  if self.statusEdit.container then -- piggyback on status
    window.windowAdd(self.statusEdit, s, 'v', true)
  else -- create our own
    window.windowAdd(self.view, s, 'h', false)
    s.fh, s.fw = 1, nil
  end
  assert(s.container)
end

Model.status=function(self, msg, kind)
  if type(msg) ~= 'string' then msg = concat(msg) end
  kind = kind and string.format('[%s] ', kind) or '[status] '
  msg = kind .. msg
  local e = self.statusEdit
  e:changeStart()
  assert(not msg:find('\n')); e:append(msg)
  pnt('Status: ', msg)
end
Model.spent=function(self)
  return civix.epoch() - self.start
end
Model.loopReturn=function(self)
  -- local spent = self:spent()
  -- if DRAW_PERIOD < spent then
  --   return true
  -- end
  return false
end

-- #####################
-- # Bindings
Model.getBinding=function(self, key)
  local b = self.bindings[self.mode]
  if 'string' == type(key) then
    return b[key]
  end
  return ds.getPath(b, key)
end

-- #####################
-- # Buffers
Model.nextBufId=function(self, id)
  id = id or table.remove(self.freeBufIds)
  if not id then id = self.freeBufId; self.freeBufId = id + 1 end
  if self.buffers[id] then error('Buffer already exists: ' .. tostring(id)) end
  return id
end
Model.newBuffer=function(self, id, s)
  id = self:nextBufId(id)
  local b = Buffer.new(s); b.id = id
  self.buffers[id] = b
  return b
end
Model.closeBuffer=function(self, b)
  local id = b.id; self.buffers[id] = nil
  if type(id) == 'number' then self.freeBufIds:add(id) end
  return b
end
Model.newEdit=function(self, bufId, bufS)
  return Edit.new(nil, self:newBuffer(bufId, bufS))
end

-- #####################
-- # Windows
Model.moveFocus=function(self, direction)
  assert(window.VIEW_DIRECTION_SET[direction])
  local sib = window.viewSiblings(self.edit)
  local e = window.focusIndexBestEffort(sib[direction], sib.index)
  if e then
    assert(ty(e) == T.Edit)
    self.edit = e
  end
end

-- #####################
--   * draw
Model.draw = function(mdl)
  mdl.h, mdl.w = mdl.term:size()
  ds.update(mdl.view, {tl=1, tc=1, th=mdl.h, tw=mdl.w})
  mdl.view:draw(mdl.term, true)
  mdl.edit:drawCursor(mdl.term)
end

-- #####################
--   * update
Model.unrecognized=function(self, keys)
  self:status('chord: ' .. concat(keys, ' '), 'unset')
end

Model.actRaw=function(self, ev)
  local act = Actions[ev[1]]
  if not act then error('unknown action: ' .. mty.fmt(ev)) end
  local out = act.fn(self, ev) or {}
  return out
end

Model.actionHandler=function(self, out, depth)
  while #out > 0 do
    local e = table.remove(out); e.depth = (depth or 1) + 1
    self.events:addBack(e)
  end
end

Model.update=function(self)
  while not self.events:isEmpty() do
    local ev = self.events:popBack();
    if (ev.depth or 1) > 12 then error('event depth: ' .. ev.depth) end
    pnt('Event: ', ev)
    local out = nil
    if self.chain then
      ds.update(self.chain, ev)
      ev = self.chain; self.chain = nil
    end
    out = self:actRaw(ev)
    if ty(out) ~= 'table' then error('action returned non-list: '..mty.fmt(out)) end
    self:actionHandler(out, ev.depth)
  end
end
-- the main loop

-- #####################
--   * step: run all pieces
Model.step=function(self)
  local key = self.inputCo()
  self.start = civix.epoch()
  if key == '^C' then
    pnt('\nctl+C received, ending\n')
    return false
  end
  if key then self.events:addFront({'rawKey', key=key}) end
  self:update()
  if self.mode == 'quit' then return false end
  self:draw()
  return true
end

Model.app=function(self)
  mty.pnt('starting app')
  self.term:clear()
  self:init()
  while true do
    if not self:step() then break end
  end
  self.term:stop()
  mty.pnt('\nExited app')
end


-- #####################
-- # Main

M.testModel = function(t, inp)
  local mdl = Model.new(t, inp)
  mdl.edit = mdl:newEdit(nil, data.TEST_MSG)
  mdl.edit.container = mdl
  mdl.view = mdl.edit; mdl:showStatus()

  return mdl, mdl.statusEdit, mdl.edit
end

return M

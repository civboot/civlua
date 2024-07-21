local mty = require'metaty'
-- Session: holds the main objects of an ed session.
--   This are not directly available to actions/etc
--   This also makes it easier to setup tests/etc.
local Session = mty'Session' {
  'ed [Ed]',
  'events [Recv]', 'evsend [Send]',
  'keys [Recv]', 'keysend [Send]',
  'logf [File]',
}

local ds = require'ds'
local log = require'ds.log'
local lap = require'lap'
local civix = require'civix'
local et = require'ele.types'
local Ed = require'ele.Ed'
local edit = require'ele.edit'
local bindings = require'ele.bindings'
local actions = require'ele.actions'

local yield = coroutine.yield

-- local FRAME = 0.05
local FRAME = 0.05

Session.init = function(T, s)
  s = s or {}
  s.ed = s.ed or Ed:init()
  s.events = lap.Recv(); s.evsend = s.events:sender()
  s.keys   = lap.Recv(); s.keysend = s.keys:sender()
  s.ed:focus(s.ed:buffer())
  return T(s)
end
-- init test session
Session.test = function(T, ed)
  local s = T:init(ed)
  s.ed.error = log.LogTable{}
  s.ed.warn  = log.warn
  return s
end
-- init (not run) real user session
Session.user = function(T, ed)
  local s = T:init(ed)
  s.ed.error = log.err
  s.ed.warn  = log.warn
  return s
end


-- run events until they are exhuasted
Session.run = function(s)
  local actions = s.ed.actions
  while #s.events > 0 do
    local ev = s.events()
    log.info('run event %q', ev)
    if not ev or not ev.action then goto cont end
    s.ed.redraw = true
    local act = ev.action; if act == 'exit' then
      s.ed.error'exit action received'
      s.ed.run = false
      break
    end
    act = actions[act]; if not act then
      s.ed.error('unknown action: %q', act)
      goto cont
    end
    local ok, err = ds.try(act, s.ed, ev, s.evsend)
    if not ok then s.ed.error('failed event %q. %q', ev, err) end
    ::cont::
  end
end

-- send chord of keys and play them (run events)
-- this is only used in tests
Session.play = function(s, chord)
  log.info('play %q', chord)
  s.keysend:extend(bindings.chord(chord))
  while (#s.keys > 0) or (#s.events > 0) do yield(true) end
  log.info('draw %q', chord)
  s.ed.display:clear(); -- normally part of resize()
  s.ed.redraw = true; s.ed:draw()
end

-- Start a user session
Session.handleEvents = function(s)
  assert(LAP_ASYNC, 'must be started in async mode')
  assert(s.ed and s.keys)
  lap.schedule(function()
    LAP_TRACE[coroutine.running()] = true
    bindings.keyactions(s.ed, s.keys, s.evsend)
  end)
  lap.schedule(function()
    LAP_TRACE[coroutine.running()] = true
    while s.ed.run do
      s.events:wait()
      s:run()
    end
    log.info'exiting sesssion run + draw'
  end)
  return s
end

-- draw coroutine
Session.draw = function(s)
   while s.ed.run do
     if s.ed.redraw then
       s.ed.display:resize()
       s.ed:draw()
       s.ed.display:draw()
       s.ed.redraw = false
     end
     yield('sleep', FRAME)
   end
end

return Session

-- User module: set up an actual user to use
local M = mod and mod'ele.user' or {}
local mty = require'metaty'
local ds = require'ds'
local log = require'ds.log'
local lap = require'lap'
local civix = require'civix'
local et = require'ele.types'
local Ed = require'ele.Ed'
local edit = require'ele.edit'
local bindings = require'ele.bindings'
local actions = require'ele.actions'

M.Session = mty'Session' {
  'ed [Ed]',
  'events [Recv]', 'evsend [Send]',
  'keys [Recv]',   'keysend [Send]',
}
M.Session.init = function(T, ed)
  local s = {ed=ed or Ed:init()}
  s.events = lap.Recv(); s.evsend = s.events:sender()
  s.keys   = lap.Recv(); s.keysend = s.keys:sender()
  return T(s)
end
-- init test session
M.Session.test = function(T, ed)
  local s = T:init(ed)
  s.ed.error = log.LogTable{}
  return s
end
-- init (not run) real user session
M.Session.user = function(T, ed)
  local s = T:init(ed)
  s.ed.error = log.error
  return s
end

-- run events until they are exhuasted
M.Session.run = function(s)
  local actions = s.ed.actions
  for ev in s.events do
    log('event', ev); if not ev or not ev.action then goto cont end
    local act = actions[ev.action]; if not act then
      s.ed:error('unknown action: %q', act)
      goto cont
    end
    local ok, err = ds.try(act, s.ed, ev, s.evsend)
    if not ok then s.ed:error('failed event %q\nError: %s', err) end
    ::cont::
  end
end

-- send chord of keys and play them (run events)
M.Session.play = function(s, chord)
  h.keysend:extend(bindings.chord(chord))
  h:run()
end

-- Start for an actual user session
M.start = function(ed, input)
  assert(LAP_ASYNC, 'must be started in async mode')
  local log = io.open('.out/LOG', 'w')
  ed.display:start(log, log)
  local s = M.Session:user(ed)
  LAP_READY[
    coroutine.create(input, s.keysend)
  ] = 'terminput'
  LAP_READY[
    coroutine.create(bindings.keyactions, ed, s.keys)
  ] = 'keyactions'
  lap.schedule(function() while ed.run do s:run() end end)
  return s
end

return M

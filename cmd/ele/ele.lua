-- extendable lua editor
local M = mod and mod'ele' or {}
local lap = require'lap'
local log = require'ds.log'

print'ele.lua'

-- shim exe function
M.exe = function(args)
  print'ele exe'
  log.info('ele exe', args)
  -- TODO: handle args
  local s = args.session or require'ele.session'.Session:user{}
  lap.async()
  require'fd'.ioAsync()
  return s, require'civix'.Lap{}:run(function()
    local term = require'civix.term'
    -- s.logf = s.logf or assert(io.open('/tmp/ele.log', 'w'))
    s.ed.display = term.FakeTerm
    -- s.ed.display:start(s.logf, s.logf)
    s:start()
    LAP_READY[
      coroutine.create(term.input, s.keys:sender())
    ] = 'terminput'
    log.info'ele started'
  end)
end

return require'shim'(M)

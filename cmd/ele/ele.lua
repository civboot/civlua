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
  assert(s.ed)
  lap.async()
  require'fd'.ioAsync()
  return s, require'civix'.Lap{}:run(function()
    local term = require'civix.term'
    s.logf = s.logf or assert(io.open('/tmp/ele.log', 'w'))
    s.ed.display = term.Term
    s.ed.display:start(s.logf, s.logf)
    print'!! print works after display start'
    log.info'!! log works after display start'
    s:start()
    lap.schedule(function()
      term.input(s.keys:sender())
    end)
    log.info'ele started'
  end)
end

return require'shim'(M)

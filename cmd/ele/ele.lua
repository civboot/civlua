-- extendable lua editor
local M = mod and mod'ele' or {}
local lap = require'lap'
local log = require'ds.log'
local fd = require'fd'
local ioopen = io.open

print'ele.lua'

-- shim exe function
M.exe = function(args)
  print'ele exe'
  log.info('ele exe', args)
  -- TODO: handle args
  local s = args.session or require'ele.session'.Session:user{}
  assert(s.ed)
  local keysend = s.keys:sender()

  local l = require'civix'.Lap{}:run(function()
    local term = require'civix.term'
    local stdout = assert(io.open('/tmp/ele.out', 'w'))
    local stderr = assert(ioopen('/tmp/ele.err', 'w'))

    s.ed.display = term.Term
    s.ed.display:start(stdout, stderr)
    print'print after display start'
    log.info'log after display start'
    s:start()
    lap.schedule(function() term.input(keysend) end)
    log.info'ele started'
  end,
  function() lap.async()
    fd.ioAsync(); io.stdout:toNonBlock(); io.stdin:toNonblock()
  end,
  function() lap.sync()
    io.stdin:toBlock(); io.stdout:toBlock(); fd.ioSync()
  end)
  return s, l
end

return require'shim'(M)

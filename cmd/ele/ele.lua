-- extendable lua editor
local M = mod and mod'ele' or {}
local lap = require'lap'
local log = require'ds.log'
local fd = require'fd'
local ioopen = io.open

CWD = CWD or os.getenv'PWD' or os.getenv'CD'

-- shim exe function
M.exe = function(args)
  print'ele exe'
  local vt = require'vt100'
  log.info('ele exe', args)
  -- TODO: handle args
  local s = args.session or require'ele.Session':user{}
  local keysend = s.keys:sender()

  local l = require'civix'.Lap{}:run(
  function() -- setup terminal and kickoff ele coroutines
    local stderr = assert(ioopen('/tmp/ele.err', 'w'))
    vt.start(stderr)

    s.ed.display = vt.Term{}
    print'print after display start'
    log.info'log after display start'
    s:handleEvents()
    lap.schedule(function()
      LAP_TRACE[coroutine.running()] = true
      log.info'start term:input()'
      s.ed.display:input(keysend)
      log.info'exit term:input()'
    end)
    lap.schedule(function()
      s:draw()
    end)
    log.info'ele started'
  end,
  function() lap.async() -- setup (async())
    fd.ioAsync()
    fd.stdin:toNonblock()
  end,
  function() lap.sync() -- teardown (sync())
    fd.stdin:toBlock()
    vt.stop()
    fd.ioSync()
  end)
  return s, l
end

return require'shim'(M)

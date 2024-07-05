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
  local term = require'civix.term'
  log.info('ele exe', args)
  -- TODO: handle args
  local s = args.session or require'ele.session'.Session:user{}
  local keysend = s.keys:sender()

  local l = require'civix'.Lap{}:run(
  function() -- setup terminal and kickoff ele coroutines
    local stdout = assert(io.open('/tmp/ele.out', 'w'))
    local stderr = assert(ioopen('/tmp/ele.err', 'w'))
    term.enterRawMode(stdout, stderr)

    s.ed.display = term.Term
    print'print after display start'
    log.info'log after display start'
    s:handleEvents()
    lap.schedule(function()
      log.info'start term.input'
      term.input(keysend)
      log.info'exit term.input'
    end)
    lap.schedule(function() s:draw() end)
    log.info'ele started'
  end,
  function() lap.async() -- setup (async())
    fd.ioAsync()
    fd.stdin:toNonblock()
  end,
  function() lap.sync() -- teardown (sync())
    fd.stdin:toBlock()
    term.exitRawMode()
    fd.ioSync()
  end)
  return s, l
end

return require'shim'(M)

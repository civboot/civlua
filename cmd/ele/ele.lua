-- extendable lua editor
local M = mod'ele'
MAIN = MAIN or M
CWD = CWD or os.getenv'PWD' or os.getenv'CD'

local shim = require'shim'
local lap = require'lap'
local fd = require'fd'
local ds = require'ds'
local log = require'ds.log'
local ac = require'asciicolor'
local vt = require'vt100'

local ioopen = io.open
local iostdout, iostderr = io.stdout, io.stderr
local sysprint = G.print

-- shim exe function
M.main = function(args)
  args = shim.parseStr(args)
  local savedmode
  log.info('ele exe', args)
  -- TODO: handle args besides paths
  local s = args.session or require'ele.Session':user{}
  local keysend = s.keys:sender()
  local iofmt   = io.fmt

  local l = require'civix'.Lap{}:run(
  function() -- setup terminal and kickoff ele coroutines
    s.ed.display = vt.Term{
      fd=io.stdout,
      styler=ac.Styler{style=ac.loadStyle()},
    }
    io.stdout = nil
    G.print = ds.eprint
    log.info'ele: started display'
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
    log.info'ele: started'
    if #args > 0 then
      for _, path in ipairs(args) do
        log.info('arg path: %q', path)
        s.ed:buffer(path)
      end
      s.ed:focus(args[1])
    end
    log.info'ele: end of setup'
  end,
  function() lap.async() -- setup: change to async()
    io.stderr = assert(ioopen('/tmp/ele.err', 'w'))
    io.fmt = require'civ'.Fmt{to=io.stderr}
    savedmode = vt.start()

    fd.ioAsync()
    fd.stdin:toNonblock()
    fd.stdout:toNonblock()
  end,
  function() lap.sync() -- teardown: change to sync()
    fd.stdout:toBlock()
    fd.stdin:toBlock()
    fd.ioSync()

    vt.stop(io.stdout, savedmode)
    io.stderr = iostderr
    io.fmt    = iofmt

  end)
  return s, l
end

if M == MAIN then
  M.main(shim.parse(arg)); os.exit(0)
end

return M

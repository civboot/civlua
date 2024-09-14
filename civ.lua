#!/usr/bin/lua
mod = mod or require'pkg'.mod

-- civ module: packaged dev environment
local M = mod'civ'

CWD = false
DOC,          METATY_CHECK  = false, false
LOGLEVEL,     LOGFN         = false, false
LAP_READY,    LAP_ASYNC     = false, false
LAP_FNS_SYNC, LAP_FNS_ASYNC = false, false
LAP_CORS,     LAP_TRACE     = false, false

local initG = {}; for k in pairs(_G) do initG[k] = true end

local shim    = require'shim'
local mty     = require'metaty'
local civtest = require'civtest'
local ds      = require'ds'
local pth     = require'ds.path'
local fd      = require'fd'

local doc   = require'doc'
local ff    = require'ff'
local ele   = require'ele'
local rock  = require'pkgrock'
local astyle = require'asciicolor.style'
civtest.assertGlobals(initG)

local sfmt = string.format


M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]

M.help = function(args, isExe)
  if #args == 0 then print(M.HELP) return end
  local ok, err = ds.try(function()
    local st = astyle.Styler{
      color=shim.color(args.color, fd.isatty(io.stdout)),
    }
    require'cxt.term'{doc(args), to=st}
    io.stdout:write'\n'
    io.stdout:flush()
  end)
  if not ok then
    mty.print(string.format('Error %s:', args[0]), err)
  end
end

shim {
  help=DOC,
  subs = {
    help = {help=M.HELP, exe=M.help},
    ele  = ele,
    ff   = ff.shim,
    rock = rock.shim,
    ['cxt.html'] = require'cxt.html'.shim,
  },
}

return M

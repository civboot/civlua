#!/usr/bin/lua
mod = mod or require'pkg'.mod

-- civ module: packaged dev environment
local M = mod'civ'

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

local doc   = require'doc'
local ff    = require'ff'
local ele   = require'ele'
local rock  = require'pkgrock'
civtest.assertGlobals(initG)


M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]
M.help = function(args, isExe)
  if #args == 0 then print(M.HELP) return end
  local ok, d = pcall(function() return doc(args[1]) end)
  if ok then print(d) else
    print('Error:', (d:match':%d+:%s*(.-)\n'))
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

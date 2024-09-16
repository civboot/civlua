#!/usr/bin/env -S lua -e "require'pkglib'()"
local pkglib = require'pkglib'
mod = mod or pkglib.mod

-- civ module: packaged dev environment
local M = mod'civ'; MAIN = MAIN or M

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

M.help = function(args, isExe)
  args = M.Help(shim.parse(args))
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

if M == MAIN then
  local cmd = table.remove(arg, 1)
  if not cmd then print'Usage: civ.lua pkg ...'; os.exit(1) end
  require(cmd).main(arg)
end
-- shim {
--   help='run a shim command from a PKG',
--   subs = {
--     -- help = {exe=M.help, help=doc{M.Help}},
--     doc  = doc.shim,
--     ele  = ele,
--     ff   = ff.shim,
--     rock = rock.shim,
--     ['cxt.html'] = require'cxt.html'.shim,
--   },
-- }

return M

#!/usr/bin/lua
DOC, FIELD_DOC                 = false, false
METATY_CHECK, METATY_DOC       = true,  true
LAP_READY,    LAP_ASYNC        = false, false
LAP_FNS_SYNC, LAP_FNS_ASYNC    = false, false

local DOC = [[civ: bundled Civboot applications]]
local M = {}

local initG = {}; for k in pairs(_G) do initG[k] = true end
local pkg     = require

local shim    = require'shim'
local mty     = require'metaty'
local civtest = require'civtest'
local doc     = require'doc'
local ds      = require'ds'

local ff    = require'ff'
local ele   = require'ele'
local rock  = require'pkgrock'
civtest.assertGlobals(initG)

M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]
M.help = function(args, isExe)
  args = shim.listSplit(args, '.')
  if #args == 0 then print(M.HELP) return end
  local path = ds.copy(args)
  local mname = table.remove(path, 1);
  local mod = package.loaded[mname] or pkg(mname)
  local obj = ds.getPath(mod, table.unpack(path)); if not obj then print(
    'ERROR: '..table.concat(path, '.')..' not found'
  )end
  print('Help: '..table.concat(args, '.'))
  print(mty.help(obj))
end

M.helpShim = {help=M.HELP, exe=M.help}

shim{
  help=DOC,
  subs = {
    help = M.helpShim,
    ele  = ele.main,
    ff   = ff.shim,
    rock = rock.shim,
    -- ['cxt.html'] = require'cxt.html'.shim,
  },
}

return M

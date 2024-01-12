#!/usr/bin/lua
METATY_CHECK, METATY_DOC = true, true
DOC = [[civ: bundled Civboot applications.

]]
local M = {}

M.dir = debug.getinfo(1).source:sub(2, -1-#'civ.lua')
function M.load(name, path)
  assert(not package.loaded[name])
  local p = dofile(M.dir..path); package.loaded[name] = p
  return p
end

local initG = {}; for k in pairs(_G) do initG[k] = true end
local pkg     = M.load('pkg',      'lib/pkg/pkg.lua')

local shim    = pkg'shim'
local mty     = pkg'metaty'
local civtest = pkg'civtest'
local doc     = pkg'doc'
local ds      = pkg'ds'

local ff  = pkg'ff'
local ele = pkg'ele'
civtest.assertGlobals(initG)

M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]
function M.help(args, isExe)
  args = shim.listSplit(args, '.')
  if #args == 0 then print(M.HELP) return end
  local path = ds.copy(args)
  local mname = table.remove(path, 1);
  local mod = package.loaded[mname] or pkg.PKGS[mname] or pkg(mname)
  local obj = ds.getPath(mod, path); if not obj then print(
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
    ['cxt.html'] = pkg'cxt.html'.shim,
  },
}

return M

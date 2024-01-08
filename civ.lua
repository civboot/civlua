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
local shim    = M.load('shim',     'lib/shim/shim.lua')
local mty     = M.load('metaty',   'lib/metaty/metaty.lua')
local doc     = M.load('doc',      'lib/doc/doc.lua')
local ds      = M.load('ds',       'lib/ds/ds.lua')
   M.load('ds.heap', 'lib/ds/ds/heap.lua')
   M.load('ds.file', 'lib/ds/ds/file.lua')
local patch   = M.load('patch',    'lib/patch/patch.lua')
local patience= M.load('patience', 'lib/patience/patience.lua')
local civtest = M.load('civtest',  'lib/civtest/civtest.lua')

M.load('tso',        'lib/tso/tso.lua')
M.load('pegl',       'lib/pegl/pegl.lua')
M.load('pegl.lua',   'lib/pegl/pegl/lua.lua')
M.load('luck',       'lib/luck/luck.lua')
M.load('cxt',        'cmd/cxt/cxt.lua')
M.load('cxt.html',   'cmd/cxt/cxt/html.lua')
M.load('civix',      'lib/civix/civix.lua')
M.load('civix.term', 'lib/civix/civix/term.lua')

local ff  = M.load('ff',   'cmd/ff/ff.lua')
            M.load('rebuf.motion', 'lib/rebuf/rebuf/motion.lua')
            M.load('rebuf.gap',    'lib/rebuf/rebuf/gap.lua')
            M.load('rebuf.buffer', 'lib/rebuf/rebuf/buffer.lua')
local ele = M.load('ele',  'cmd/ele/ele.lua')
civtest.assertGlobals(initG)

M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]
function M.help(args, isExe)
  args = shim.listSplit(args, '.')
  if #args == 0 then print(M.HELP) return end
  local path = ds.copy(args)
  local mname = table.remove(path, 1);
  local mod = package.loaded[mname] or require(mname)
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
    ['cxt.html'] = require'cxt.html'.shim,
  },
}

return M

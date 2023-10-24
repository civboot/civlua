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
local shim    = M.load('shim',     'shim/shim.lua')
local mty     = M.load('metaty',   'metaty/metaty.lua')
local doc     = M.load('doc',      'doc/doc.lua')
local ds      = M.load('ds',       'ds/ds.lua')
   M.load('ds.heap', 'ds/ds/heap.lua')
local smol    = M.load('smol',     'smol/smol.lua')
   M.load('smol.lzw',     'smol/smol/lzw.lua')
   M.load('smol.verify',     'smol/smol/verify.lua')
local patience= M.load('patience', 'patience/patience.lua')
local civtest = M.load('civtest',  'civtest/civtest.lua')

M.load('pegl',       'pegl/pegl.lua')
M.load('pegl.lua',   'pegl/pegl/lua.lua')
M.load('civix',      'civix/civix.lua')
M.load('civix.term', 'civix/civix/term.lua')

local ff  = M.load('ff',   'ff/ff.lua')
            M.load('rebuf.motion', 'rebuf/rebuf/motion.lua')
            M.load('rebuf.gap', 'rebuf/rebuf/gap.lua')
            M.load('rebuf.buffer', 'rebuf/rebuf/buffer.lua')
local ele = M.load('ele',  'ele/ele.lua')
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
  },
}

return M

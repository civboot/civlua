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
initG.none = true -- expected in ds.lua
local shim = M.load('shim',    'shim/shim.lua')
local mty = M.load('metaty',  'metaty/metaty.lua')
M.load('ds',      'ds/ds.lua')
local civtest = M.load('civtest', 'civtest/civtest.lua')

M.load('pegl',       'pegl/pegl.lua')
M.load('pegl.lua',   'pegl/pegl/lua.lua')
M.load('civix',      'civix/civix.lua')
M.load('civix.term', 'civix/civix/term.lua')

local ff  = M.load('ff',   'ff/ff.lua')
local ele = M.load('ele',  'ele/ele.lua')
civtest.assertGlobals(initG)

shim{
  help=DOC,
  subs = {
    ele = ele.main,
    ff = ff.shim,
  },
}

return M

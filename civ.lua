#!/usr/bin/lua
DOC = [[civ: bundled Civboot applications.

Bash recommendation: `alias ,=/path/to/civ.lua`
Now execute sub-commands with:
  , find --dir --pat 'some pattern'

Note: This is a self-loading Lua module, just execute and it runs!
]]
local M = {}

M.dir = debug.getinfo(1).source:sub(2, -1-#'civ.lua')
function M.load(name, path)
  assert(not package.loaded[name])
  local p = dofile(M.dir..path); package.loaded[name] = p
  return p
end

local initG = {}; for k in pairs(_G) do initG[k] = true end
local shim = M.load('shim',    'shim/shim.lua')
local mty = M.load('metaty',  'metaty/metaty.lua')
M.load('ds',      'ds/ds.lua')
local civtest = M.load('civtest', 'civtest/civtest.lua')

M.load('pegl',       'pegl/pegl.lua')
M.load('pegl.lua',   'pegl/pegl/lua.lua')
M.load('civix',      'civix/civix.lua')
M.load('civix.term', 'civix/civix/term.lua')
local ele = M.load('ele',        'ele/ele.lua')
civtest.assertGlobals(initG)

shim{
  help=DOC,
  subs = {
    ele=ele.main,
  },
}

return M

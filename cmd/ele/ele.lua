local shim = require'shim'
local mty = require'metaty'
local term = require'civix.term'
local sfmt = string.format

local dir = debug.getinfo(1).source:sub(2, -1-#'ele.lua')
local function load(name, path)
  assert(not package.loaded[name], name)
  local p = dofile(dir..path); package.loaded[name] = p
  return p
end

load('ele.FakeTerm', 'ele/FakeTerm.lua')
load('ele.data',     'ele/data.lua')

load('ele.types',    'ele/types.lua')

load('ele.keys',     'ele/keys.lua')
load('ele.window',   'ele/window.lua')
load('ele.edit',     'ele/edit.lua')
load('ele.action',   'ele/action.lua')
load('ele.bindings', 'ele/bindings.lua')
local model = load('ele.model',    'ele/model.lua')

local M = {}
M.main = function()
  local log, tm = io.open('.out/LOG', 'w'), term.Term
  tm:start(log, log)
  local inp = term.niceinput()
  local mdl = model.testModel(term.Term, inp)
  mdl:app()
end

shim{
  help='ele: the extendable lua text editor',
  exe=M.main,
}

return M

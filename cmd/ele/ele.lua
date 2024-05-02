local pkg = require'pkglib'
local shim = require'shim'
local mty  = require'metaty'
local term = require'civix.term'
local sfmt = string.format

local model = require'ele.model'

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

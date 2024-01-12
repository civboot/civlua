local pkg = require'pkg'
local shim = pkg'shim'
local mty = pkg'metaty'
local term = pkg'civix.term'
local sfmt = string.format

local model = pkg'ele.model'

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

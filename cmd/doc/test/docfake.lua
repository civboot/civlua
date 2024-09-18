--- fake lua module for testing doc.
---
--- module documentation.
local M = mod'docfake'

local mty = require'metaty'

--- documented module constant
M.CONSTANT = 2

M.NODOC = {3, 4, a=5}

--- this is a function.
--- it has documentation.
M.fun1 = function() end --> thing

--- Documentation for A
M.A = mty'A' {
  'a1 [string]: a1 docs\n'
..'are the best docs',
}

--- docs for meth1
M.A.meth1 = function() end --> thing

return M

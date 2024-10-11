local G = G or _G

--- small compression algorithms
local M = G.mod and mod'smol' or {}

local S = require'smol.sys'

--- apply an encoded rdelta to its base string to get the change.
--- ["Note: base will be an empty string if this is pure compression.]
M.rdecode = S.rdecode --(base, encoded) -> change

return M

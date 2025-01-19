local G = G or _G
--- civdb: minimalistic CRUD database
local M = G.mod and mod'civdb' or setmetatable({}, {})
local S = require'civdb.sys'

M.encode, M.decode = S.encode, S.decode
return M

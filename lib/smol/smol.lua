local G = G or _G

--- small compression algorithms
local M = G.mod and mod'smol' or {}
local S = require'smol.sys'

local mty = require'metaty'

M.XConfig = mty'XConfig' {
  'fp4po2 [int]: max size of len4 fingerprint table', fp4po2=14,
}

M.Smol = mty'Smol' {
  'x [smol.X]: holds settings and buffers for smol operations',
}

getmetatable(M.Smol).__call = function(T, xConfig)
  xConfig = M.XConfig(x)
end



return M

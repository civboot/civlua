local G = G or _G

--- acsyntax: asciicolor syntax highlighting.
local M = G.mod and G.mod'acsyntax' or {}

local mty = require'metaty'
local pegl = require'pegl'

M.Highlighter = mty'Highlighter' {
  'rootSpec [pegl.Config]: the pegl root spec',
  'rootNode: pegl root node to parse (typically pegl.Or)',
}

return M

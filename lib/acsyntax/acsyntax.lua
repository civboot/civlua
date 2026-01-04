local G = G or _G

--- acsyntax: asciicolor syntax highlighting.
local M = G.mod and G.mod'acsyntax' or {}

local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local pegl = require'pegl'
local pegl_lua = require'pegl.lua'
local EdFile = require'lines.EdFile'

local construct = mty.construct

--- The highlighter object determines how to parse and
--- highlight a text file's syntax.
M.Highlighter = mty'Highlighter' {
 [[config [pegl.Config]: the pegl root configuration.
   Typically this should have lenient=true to allow for
   syntax errors to happen but parsing to continue.
 ]],
 [[spec: pegl root spec to parse, aka the grammar tree.
   This should typically be a "lenient" spec with a fallback
   which can parse any symbol.
 ]],

 [[style [table]: a table of name|kind -> 'style' (asciicolor style)
   (name takes precendence).

   The value can be either the style literal or a [$fn(node) -> style].

   The Highlighter will call for each node's kind, if the style isn't
   found it will be called again for all node children.
 ]],

 [[builtin [list]: list of builtin names.]]

  'acStyle {string, string}: table of style -> asciicolor fg/bg',

  'dir [string]: base dir where highlighting is stored',
}

getmetatable(M.Highlighter).__call = function(T, t)
  for _, key in ipairs(t.builtin) do t.builtin[key] = 1 end
  return construct(T, t)
end

M.Highlighter._highlight = function(hl, modTime, node, fgLf, bgLf)
  local n = node.name or node.kind
  local sty = style[n]
  if sty then -- found style, write it out.
  else -- write "no style" and continue.
  end
end

--- Highlight the LinesFile (lf) returning a fg and bg lines file.
M.Highlighter.highlight = function(hl, lf) --> fgLf, bgLf
  local modTime = ix.stat(hl.f):modified()
  local root = pegl.parse(lf, hl.spec, hl.config)

  local path = pth.concat(hl.dir, lf:path())
  ix.mkDirs( (pth.last(path)) )

  local fgPath, bgPath = path..'fg', path..'bg'
  local fgLf = assert(EdFile(fgPath, 'w'))
  local bgLf = assert(EdFile(bgPath, 'w'))

  hl:_highlight(modTime, root, fgFile, bgFile)

  fgFile:close(), bgFile:close()
  return fgPath, bgPath
end

return M

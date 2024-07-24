-- style text from a user's config.
local M = mod and mod'asciicolor.style' or {}

local mty = require'metaty'
local pth = require'ds.path'
local ac = require'asciicolor'

M.CONFIG_PATH = '.config/colors.lua'

-- Dark Mode Default
M.DARK = {
  -- Find tools (i.e. ff)
  path  = 'G', -- file/dir path
  match = 'FZ',-- search match
  meta  = 'd', -- Meta=metadata, aka line number / etc

  -- Code Syntax
  keyword       = 'R', -- for while do etc
  symbol        = 'r', -- = + . etc
  builtin       = 'p', -- builtin fns/mods/names: io sys self etc
  commentbox    = 'g', -- start/end of comment: -- // /**/ etc
  commentbody   = 'g', -- content of comment:  /*content*/
  stringbox     = 'M', -- start/end of string: '' "" [[]] etc
  stringbody    = 'm', -- content of string:   "content"
  char          = 'm', -- single character: 'c'
  number        = 'm', -- float or integer: 0 1.0 0xFF etc
  literal       = 'm', -- other literal: null, bool, date, regex, etc
  call          = 'c', -- function call: foo()
  dispatch      = 'c', -- method call:   obj:foo()
}

M.Styler = mty'Styler' {
  'writer [AcWriter]',
  'colorFB [fn]: with signature of asciicolor.colorFB',
    colorFB = require'vt100'.colorFB,
  "styles [table]: table of 'fb' styles, aka the user's config",
  'color [boolean]: disable color if set to false', color=true,
}

-- write plain text
M.Sytler.write = function(st, ...) -- write(...)
  return st.writer:acwrite(nil, nil, ...)
end
-- Example: st:style('path', 'path/to/thing.txt', '\n')
M.Styler.style = function(st, style, str, ...) --> write(str, ...)
  if not st.color then return st:write(str, ...) end
  local len, fb = #str, st.styles[style] or ''
  return st.writer:acwrite(
    fb:sub(1,1):rep(len), fb:sub(2,2):rep(len),
    str, ...)
end

M.stylePath = function() return pth.concat{pth.home(), CONFIG_PATH} end
M.load = function(path)
  path = path or M.stylePath()
  local f = io.open(path); if f then f:close() -- path exists
    return require'luck'.load(path)
  end
  return M.DARK -- path DNE
end

return M

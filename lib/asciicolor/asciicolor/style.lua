-- style text from a user's config.
local M = mod and mod'asciicolor.style' or {}

local mty = require'metaty'
local ds = require'ds'
local log = require'ds.log'
local pth = require'ds.path'
local ac = require'asciicolor'

M.CONFIG_PATH = '.config/colors.luck'

M.dark = {
  -- Find tools (i.e. ff)
  path  = 'M',  -- file/dir path
  match = 'Bf', -- search match
  line  = 'ld', -- line number / etc
  meta  = 'd',  -- Meta=metadata such as description of ops, etc
  error = 'Wr',

  -- Code Syntax
  keyword       = 'R', -- for while do etc
  symbol        = 'r', -- = + . etc
  builtin       = 'p', -- builtin fns/mods/names: io sys self etc
  commentbox    = 'G', -- start/end of comment: -- // /**/ etc
  commentbody   = 'g', -- content of comment:  /*content*/
  stringbox     = 'M', -- start/end of string: '' "" [[]] etc
  stringbody    = 'm', -- content of string:   "content"
  char          = 'm', -- single character: 'c'
  number        = 'm', -- float or integer: 0 1.0 0xFF etc
  literal       = 'm', -- other literal: null, bool, date, regex, etc
  call          = 'c', -- function call: foo()
  dispatch      = 'c', -- object.method called: obj.foo(), obj:foo()
}
-- TODO: light

M.mode = function() return CLIMODE or os.getenv'CLIMODE' end

M.stylePath = function() return pth.concat{pth.home(), CONFIG_PATH} end
M.loadStyle = function(path, mode)
  path = path or M.stylePath()
  mode = mode or M.mode() or 'dark'
  local style = M[mode]
  local f = io.open(path); if f then f:close() -- path exists
    local cfg = require'luck'.load(path, {MODE = mode})
    return ds.update(ds.copy(style), cfg)
  end
  return style
end

M.Styler = mty'Styler' {
  'acwriter [AcWriter]: see vt100.AcWriter as example',
  "styles [table]: table of 'fb' styles, aka the user's config",
  'color [boolean]: disables color if set to false',
}

M.Styler.flush = function(st) return st.acwriter:flush() end

-- Example: st:styled('path', 'path/to/foo.txt', '\n')
M.Styler.styled = function(st, style, str, ...)
  if not st.color then return st.acwriter:write(str, ...) end
  local len, fb = #str, st.styles[style] or ''
  return st.acwriter:acwrite(
    fb:sub(1,1):rep(len), fb:sub(2,2):rep(len),
    str, ...)
end

-- write as plain
M.Styler.write = function(st, ...)
  return st.acwriter:acwrite(nil, nil, ...)
end

return M

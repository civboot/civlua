local G = G or _G

--- style text from a user's config.
local M = G.mod and G.mod'asciicolor.style' or {}

local shim = require'shim'
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local pth = require'ds.path'
local ac = require'asciicolor'
local fd = require'fd'
local civix = require'civix'

local construct, newindex = mty.construct, mty.newindex
local sfmt = string.format

M.CONFIG_PATH = '.config/colors.luck'

M.dark = {
  -- Find tools (i.e. ff)
  path  = 'm',  -- file/dir path
  match = 'Bf', -- search match
  line  = 'ld', -- line number / etc
  meta  = 'd',  -- Meta=metadata such as description of ops, etc
  notify = 'C', -- make very visible
  error = 'Wr',
  base   = 'F', basel   = 'Wf', -- base(line),   aka removed text
  change = 'G', changel = 'Wg', -- change(line), aka added text
  empty  = 'zd',

  -- Document Styles
  code = 'hb',
  bold = 'Z', ul = 'zZ', boldul = 'ZZ',
  h1 = 'N', h2 = 'S', h3 = 'W', h4 = 'Z',

  -- Code Syntax
  api           = 'G', -- api, i.e. public function/class name
  type          = 'h', -- type signature
  var           = 'g', -- variable name
  keyword       = 'R', -- for while do etc
  symbol        = 'r', -- = + . etc
  builtin       = 'p', -- builtin fns/mods/names: io sys self etc
  commentbox    = 'bw', -- start/end of comment: -- // /**/ etc
  comment       = 'zb', -- content of comment:  /*content*/
  stringbox     = 'd', -- start/end of string: '' "" [[]] etc
  string        = 'm', -- content of string inside quotes
  char          = 'm', -- single character: 'c'
  number        = 'm', -- float or integer: 0 1.0 0xFF etc
  literal       = 'm', -- other literal: null, bool, date, regex, etc
  call          = 'c', -- function call: foo()
  dispatch      = 'c', -- object.method called: obj.foo(), obj:foo()
}
-- TODO: light

M.mode = function() return G.CLIMODE or os.getenv'CLIMODE' end

M.stylePath = function() return pth.concat{pth.home(), CONFIG_PATH} end

M.loadStyle = function(mode, path)
  mode = mode or M.mode() or 'dark'
  path = (path == true) and M.stylePath() or path
  local style = M[mode] or error('styles not found: '..mode)
  if path and civix.isFile(path) then
    log.info('loading style from %s', path)
    local cfg = require'luck'.load(path, {MODE = mode})
    return ds.update(ds.copy(style), cfg)
  end
  return style
end

--- Create a styler
---
--- Note: pass f (file) to create the default AcWriter with the file.
--- Note: pass mode, stylepath to control loadStyle
M.Styler = mty'Styler' {
  'acwriter [AcWriter]',
  "style [table]: default=loadStyle()",
}

M.Styler.__tostring = function() return 'Styler{...}' end

M.Styler.level = function(st, add) return st.acwriter.f:level(add) end
M.Styler.flush = function(st) return st.acwriter:flush() end

--- Example: st:styled('path', 'path/to/foo.txt', '\n')
M.Styler.styled = function(st, style, str, ...)
  local len, fb = #str, st.style[style] or ''
  return st.acwriter:acwrite(
    fb:sub(1,1):rep(len), fb:sub(2,2):rep(len),
    str, ...)
end

--- write as plain
M.Styler.write = function(st, ...)
  return st.acwriter:acwrite(nil, nil, ...)
end

M.Styler.__newindex = function(st, k, v)
  if type(k) ~= 'number' then return newindex(st, k, v) end
  assert(k == 1, 'cannot push non 1')
  st.acwriter:write(v)
end

return M

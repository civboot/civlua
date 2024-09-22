local G = G or _G

-- style text from a user's config.
local M = mod and mod'asciicolor.style' or {}

local shim = require'shim'
local mty = require'metaty'
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

M.defaultAcWriter = function(f)
  f = f or io.stdout
  f = (mty.ty(f) == mty.Fmt) and f or mty.Fmt:pretty{to=f}
  return require'vt100.AcWriter'{f=f}
end

-- Create a styler
--
-- Note: pass f (file) to create the default AcWriter with the file.
-- Note: pass mode, stylepath to control loadStyle
M.Styler = mty'Styler' {
  'acwriter [AcWriter]: default=defaultAcWriter()',
  "style [table]: default=loadStyle()",
  'color [boolean]: disables color if set to false', color=true
}

--- Get the default styler.
---
--- Example: [$styler = style.Styler(io.stdout, args.color)]
M.Styler.default = function(T, to--[[io.stdout]], colorArg) --> Styler
  to = to or io.stdout
  return M.Styler {
    acwriter = M.defaultAcWriter(to),
    style = M.loadStyle(),
    color = shim.color(colorArg, fd.isatty(to)),
  }
end

getmetatable(M.Styler).__call = function(T, t)
  t = t or {}
  t.acwriter = t.acwriter or M.defaultAcWriter(ds.popk(t, 'f'))
  t.style = t.style or M.loadStyle(
    ds.popk(t, 'mode'), ds.popk(t, 'stylepath'))
  t.color = t.color == nil and true or t.color
  return construct(T, t)
end
M.Styler.__tostring = function() return 'Styler{...}' end

M.Styler.level = function(st, add) return st.acwriter.f:level(add) end
M.Styler.flush = function(st) return st.acwriter:flush() end

-- Example: st:styled('path', 'path/to/foo.txt', '\n')
M.Styler.styled = function(st, style, str, ...)
  if not st.color then return st.acwriter:write(str, ...) end
  local len, fb = #str, st.style[style] or ''
  return st.acwriter:acwrite(
    fb:sub(1,1):rep(len), fb:sub(2,2):rep(len),
    str, ...)
end

-- write as plain
M.Styler.write = function(st, ...)
  return st.acwriter:acwrite(nil, nil, ...)
end

M.Styler.__newindex = function(st, k, v)
  if type(k) ~= 'number' then return newindex(st, k, v) end
  assert(k == 1, 'cannot push non 1')
  st.acwriter:write(v)
end

return M

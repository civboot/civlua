-- asciicolor: encode text color and style with a single ascii character
local M = mod and mod'asciicolor' or {}

local shim = require'shim'
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local pth = require'ds.path'
local fd = require'fd'
local civix = require'civix'

local construct, newindex = mty.construct, mty.newindex
local sfmt = string.format

M.CONFIG_PATH = '.config/colors.luck'

--- typosafe mapping of asciicode -> fullname
---
--- [" Note: These map to the available colors in a VT100 terminal emulator,
---    See the vt100 module for that implementation]
M.Color = ds.TypoSafe{
  z = 'zero', [' '] = 'zero', [''] = 'zero', -- aka default.

  --  (dark)           (light)
  b = 'black',         w = 'white',
  d = 'darkgrey',      l = 'lightgrey',
  r = 'red',           p = 'pink',
  y = 'yellow',        h = 'honey',
  g = 'green',         t = 'tea',
  c = 'cyan',          a = 'aqua',
  n = 'navy',          s = 'sky', -- blue
  m = 'magenta',       f = 'fuschia',
}

--- typosafe mapping of fullname -> asciichar
M.Ascii = mod and mod'Ascii' or {}
for k, v in pairs(M.Color) do M.Ascii[v] = k end
M.Ascii.zero = 'z' -- hardocde as there are 3 possibilities

--- makes [$' '] and [$''] both convert to [$'z']
--- as well as check that the ascii code is valid.
local CODES = {}; do
  for k in pairs(M.Color) do CODES[k] = k end
  local UC = {}; for k in pairs(M.Color) do
    CODES[k:upper()] = k:upper()
  end
  CODES['z'] = 'z'; CODES[' '] = 'z'; CODES[''] = 'z'
  CODES['Z'] = 'Z'
end
M.CODES = CODES

M.assertcode = function(ac) --> single leter (or error)
  return CODES[ac] or error(sfmt('invalid ascii color: %q', ac))
end

--- Dark mode styles (defaults)
M.dark = {
  -- Find tools (i.e. ff)
  path  = 'm',  -- file/dir path
  match = 'Bf', -- search match
  line  = 'ld', -- line number / etc
  meta  = 'd',  -- Meta=metadata such as description of ops, etc
  -- TODO: rename notice
  notify = 'C', -- make very visible
  error = 'Wr',
  base   = 'F', basel   = 'Wf', -- base(line),   aka removed text
  change = 'G', changel = 'Wg', -- change(line), aka added text
  empty  = 'zd',
  ref    = 'cZ',

  -- Document Styles
  code = 'hb',
  bold = 'Z', ul = 'zZ', boldul = 'ZZ',
  h1 = 'N', h2 = 'S', h3 = 'W', h4 = 'Z',

  -- Code Syntax
  api           = 'G', -- api, i.e. public function/class name
  type          = 'h', -- type signature
  var           = 'G', -- variable name
  keyword       = 'R', -- for while do etc
  symbol        = 'A', -- = + . { } etc
  builtin       = 'p', -- builtin fns/mods/names: io sys self etc
  commentbox    = 'bw', -- start/end of comment: -- // /**/ etc
  comment       = 'zb', -- content of comment:  /*content*/
  stringbox     = 'd', -- start/end of string: '' "" [[]] etc
  string        = 'g', -- content of string inside quotes
  key           = 'T', -- key in map/struct/etc
  char          = 'g', -- single character: 'c'
  number        = 'N', -- float or integer: 0 1.0 0xFF etc
  literal       = 'h', -- other literal: null, bool, date, regex, etc
  call          = 'c', -- function call: foo()
  dispatch      = 'C', -- object.method called: obj.foo(), obj:foo()
}

-- TODO: light-mode styles

M.mode = function() return G.CLIMODE or os.getenv'CLIMODE' end

M.stylePath = function() return pth.concat{pth.home(), CONFIG_PATH} end

M.loadStyle = function(mode, path)
  mode = mode or M.mode() or 'dark'
  path = (path == true) and M.stylePath() or path
  local style = M[mode] or error('styles not found: '..mode)
  if path and civix.isFile(path) then
    log.info('loading style from %s', path)
    local cfg = require'luck'.load(path, {MODE = mode})
    return ds.update(table.update({}, style), cfg)
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

--- create a Fmt with sensible defaults from the config
M.Fmt = function(t)
  assert(t.to, 'must set to = the output')
  if t.style == nil then t.style = shim.getEnvBool'COLOR' end
  if t.style or (t.style==nil) and fd.isatty(t.to) then
    t.style, t.to = true, M.Styler {
      acwriter = require'vt100.AcWriter'{f=t.to},
      style = M.loadStyle(),
    }
  end
  return fmt.Fmt(t)
end

return M

-- asciicolor: encode text color and style with a single ascii character
local M = mod and mod'asciicolor' or {}

local mty = require'metaty'
local ds  = require'ds'
local sfmt = string.format

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

return M

-- asciicolor: see README.md for details.
local M = mod and mod'asciicolor' or {}

local mty = require'metaty'
local sfmt = string.format
local strup, strlow = string.upper, string.lower

-- mapping of asciicode -> fullname
M.Color = {
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
local Color = M.Color

-- mapping of fullname -> asciichar
M.Ascii = {}; for k, v in pairs(M.Color) do M.Ascii[v] = k end
M.Ascii.zero = 'z' -- hardocde as there are 3 possibilities

M.fgColor = function(c) --> colorCode
  return M.FgColor[assert(M.AsciiColor[lower(c or 'z')], c)]
end
M.bgColor = function(c) --> colorCode
  return M.BgColor[assert(M.AsciiColor[lower(c or 'z')], c)]
end

-- return the string if it is only uppercase characters
-- * used for determining bold/underline
M.isupper = function(c) return c:match'^%u+$' end --> string?

local nextline = function(f) return f:write'\n' end

-- AcFile type
--   fields: f, _fg, _bg, colorFB[fn(f, fgc, bgc)], nextline(f)
M.AcFile = setmetatable({
  __name = 'AcFile',
  write = function(af, ...)
    local f = af.f
    local fg, bg = af._fg, af._bg
    if fg ~= 'z' or bg ~= 'z' then
      af.colorFB(f, 'z', 'z', fg, bg)
      af._fg, af._bg = 'z', 'z'
    end
    return f:write(...)
  end,
}, {
  __name = 'AcFileTy',
  __call = function(T, t) return setmetatable(t, T) end,
})
M.AcFile.__index = M.AcFile

-- makes ' ' and '' both convert to 'z'
-- as well as check that the ascii code is valid.
M.CODES = {}; do
  for k in pairs(M.Color) do M.CODES[k] = k end
  local UC = {}; for k in pairs(M.Color) do
    M.CODES[upper(k)] = CODEs[upper(k)]
  end
  M.CODES[' '] = 'z'; M.CODES[''] = 'z'
end

M.assertcode = function(ac) --> single leter (or error)
  return CODES[ac] or error(sfmt('invalid ascii color: %q', ac))
end

return M

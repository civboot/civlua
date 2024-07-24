-- asciicolor: see README.md for details.
local M = mod and mod'asciicolor' or {}

local mty = require'metaty'
local sfmt = string.format

-- typosafe mapping of asciicode -> fullname
M.Color = mod and mod'Color' or {}
for k, v in pairs({
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
}) do M.Color[k] = v end
local Color = M.Color
if getmetatable(Color) then -- if mod did it's thing
  Color.__name = nil; getmetatable(Color).__name = 'Color'
end

-- typosafe mapping of fullname -> asciichar
M.Ascii = mod and mod'Ascii' or {}
for k, v in pairs(M.Color) do M.Ascii[v] = k end
M.Ascii.zero = 'z' -- hardocde as there are 3 possibilities

M.fgColor = function(c) --> colorCode
  return M.FgColor[assert(M.AsciiColor[lower(c or 'z')], c)]
end
M.bgColor = function(c) --> colorCode
  return M.BgColor[assert(M.AsciiColor[lower(c or 'z')], c)]
end

-- return the string if it is only uppercase letters
M.isupper = function(c) return c:match'^%u+$' end --> string?

-- return the string if it is only lowercase letters
M.islower = function(c) return c:match'^%l+$' end --> string?

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

--------------------------
-- Writing Logic
-- These help implement logic for writing to a terminal-like
-- interface.
-- The 'af' object must have fg/bg fields for current fg/bg ascii code.
--   as well as a "colored" field which can disable color writing.
-- It must also provide a colorFB(f, fgnew, bgnew, fgcur, bgcur) method to change
-- the color

M.write = function(f, af, colorFB, ...)
  if not af.colored then return af.f:write(...) end
  local f, fg, bg = af.f, af.fg, af.bg
  if fg ~= 'z' or bg ~= 'z' then
    af:colorFB('z', 'z', fg, bg)
    af.fg, af.bg = 'z', 'z'
  end
  return f:write(...)
end

-- write to the terminal-like file using colors fg and bg
M.acwrite = function(af, fg, bg, str, ...)
  if not af.colored then return af.f:write(...) end
  if fg == nil and bg == nil then
    return af:write(af, str, ...)
  end
  local f, fg, bg, colorFB = af.f, af._fg, af.bg, colorFB
  local si = 1
  for i=1,#str do
    local chr, f, b = str:sub(i,i), fg:sub(i,i), bg:sub(i,i)
    f, b = acode(f), acode(b)
    if f ~= fg or b ~= bg then
      f:write(str:sub(si, i-1)) -- write in previous color
      si = i
      colorFB(f, f, b, fg, bg)
      fg, bg = f, b
    end
  end
  if #str - si > 0 then f:write(str:sub(si)) end -- write remainder
  if select('#', ...) > 0 then -- write ... as default colors
    colorFB(f, 'z', 'z', fg, bg)
    fg, bg = 'z', 'z'
    f:write(...)
  end
  af._fg, af._bg = fg, bg
end

return M

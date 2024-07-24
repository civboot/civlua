local mty = require'metaty'
local ac = require'asciicolor'

local acode = ac.assertcode

-- AcFile type
--   fields: f, _fg, _bg, colorFB[fn(f, fgc, bgc)], nextline(f)
local AcFile = mty'AcFile' {
  'f [file]',
  '_fg [string]: foreground char',
  '_bg[string]: background char',
  'colorFB[fn]: function(f, fgNew, bgNew, fgCur, bgCur)',
  -- TODO: add colored
}

AcFile.write = function(af, ...)
  local f = af.f
  local fg, bg = af._fg, af._bg
  if fg ~= 'z' or bg ~= 'z' then
    af.colorFB(f, 'z', 'z', fg, bg)
    af._fg, af._bg = 'z', 'z'
  end
  return f:write(...)
end

-- write to the terminal-like file using colors fg and bg
AcFile.acwrite = function(af, fg, bg, str, ...)
  if fg == nil and bg == nil then return af:write(af, str, ...) end
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

return AcFile

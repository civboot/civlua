local mty = require'metaty'
local acwrite = require'vt100'.acwrite
local colorFB = require'vt100'.colorFB

local AcWriter = mty'vt100.AcWriter' {
  'f  [file]',
  'fg [string]: current fg',
  'bg [string]: current bg',
}

AcWriter.flush = function(aw) return aw.f:flush() end

AcWriter.acwrite = function(af, fgstr, bgstr, ...)
  local w1, w2
  aw.fg, aw.bg, w1, w2 = acwrite(colorFB, aw.fg, aw.bg, fgstr, bgstr, ...)
  return w1, w2
end
AcWriter.write = function(aw, ...) return aw:acwrite(nil, nil, ...) end

return AcWriter

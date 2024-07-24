local mty = require'metaty'
local acwrite = require'vt100'.acwrite
local colorFB = require'vt100'.colorFB

-- AcWriter, typically used with asciicolors.Styler
local AcWriter = mty'vt100.AcWriter' {
  'f  [file]',
  'fg [string]: current foreground ac letter',
  'bg [string]: current background ac letter',
}

AcWriter.flush = function(aw) return aw.f:flush() end

-- :acwrite(fgstr, bgstr, str, ...): writes str with style of fg/bg str
AcWriter.acwrite = function(af, fgstr, bgstr, ...) --> write(...)
  local w1, w2
  aw.fg, aw.bg, w1, w2 = acwrite(colorFB, aw.fg, aw.bg, fgstr, bgstr, ...)
  return w1, w2
end
-- write plain
AcWriter.write = function(aw, ...) return aw:acwrite(nil, nil, ...) end

return AcWriter

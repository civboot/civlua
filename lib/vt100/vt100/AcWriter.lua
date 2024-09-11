local mty = require'metaty'
local log = require'ds.log'
local acwrite = require'vt100'.acwrite
local colorFB = require'vt100'.colorFB

-- a file-like writer which keeps track of fg and bg colors
--
-- Typically used with asciicolors.Styler
local AcWriter = mty'vt100.AcWriter' {
  'f  [file]',
  'fg [string]: current foreground ac letter', fg='z',
  'bg [string]: current background ac letter', bg='z',
}

AcWriter.flush = function(aw) return aw.f:flush() end

-- :acwrite(fgstr, bgstr, str, ...): writes str with style of fg/bg str
AcWriter.acwrite = function(aw, fgstr, bgstr, ...) --> write(...)
  local w1, w2
  aw.fg, aw.bg, w1, w2 = acwrite(
    aw.f, colorFB, aw.fg, aw.bg, fgstr, bgstr, ...)
  return w1, w2
end
-- write plain
AcWriter.write = function(aw, ...) return aw:acwrite(nil, nil, ...) end

return AcWriter

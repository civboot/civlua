local mty = require'metaty'
local log = require'ds.log'
local acwrite = require'vt100'.acwrite
local colorFB = require'vt100'.colorFB

--- A file-like writer which keeps track of fg and bg colors,
--- typically used with [<#asciicolor.Styler>]
local AcWriter = mty'vt100.AcWriter' {
  'f  [file]',
  'fg [string]: current foreground ac letter', fg='z',
  'bg [string]: current background ac letter', bg='z',
}

function AcWriter:flush() return self.f:flush() end

--- [$:acwrite(fgstr, bgstr, str, ...)]: writes str with style of fg/bg str
function AcWriter:acwrite(fgstr, bgstr, ...) --> write(...)
  local w1, w2
  self.fg, self.bg, w1, w2 = acwrite(
    self.f, colorFB, self.fg, self.bg, fgstr, bgstr, ...)
  return w1, w2
end
--- write plain
function AcWriter:write(...) return self:acwrite(nil, nil, ...) end

return AcWriter

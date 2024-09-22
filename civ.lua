#!/usr/bin/env -S lua -e "require'pkglib'()"
local G = G or _G

-- civ module: packaged dev environment
local M = G.mod'civ'; G.MAIN = G.MAIN or M
require'pkglib'()
G.METATY_CHECK = true

local fmt = require'fmt'
local fd  = require'fd'
local ac  = require'asciicolor'
local acs = require'asciicolor.style'
local AcWriter = require'vt100.AcWriter'
local shim = require'shim'

local SETUP = false
M.setupFmt = function()
  if SETUP then return end
  SETUP = true
  local to, style = io.stderr, false
  if fd.isatty(io.stderr) then
    style = shim.getEnvBool'COLOR'
    if style or (style == nil) then
      local styler = acs.Styler {
        acwriter = AcWriter {f=io.stderr},
        style = acs.loadStyle(),
      }
      to, style = styler, true
    end
  end
  io.fmt = fmt.Fmt{to=to, style=style}
end

M.main = function(arg) --> int: return code
  M.setupFmt()
  local cmd = table.remove(arg, 1)
  if not cmd then
    io.fmt:styled('error', 'Usage: civ.lua pkg ...')
    return 1
  end
  require(cmd).main(shim.parse(arg))
end

if M == MAIN then
  os.exit(M.main(arg))
end

return M

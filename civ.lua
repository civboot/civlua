#!/usr/bin/env -S lua -e "require'pkglib'()"
local pkglib = require'pkglib'
mod = mod or pkglib.mod

-- civ module: packaged dev environment
local M = mod'civ'; MAIN = MAIN or M

CWD = false
DOC,          METATY_CHECK  = false, false
LOGLEVEL,     LOGFN         = false, false
LAP_READY,    LAP_ASYNC     = false, false
LAP_FNS_SYNC, LAP_FNS_ASYNC = false, false
LAP_CORS,     LAP_TRACE     = false, false

local initG = {}; for k in pairs(_G) do initG[k] = true end

local shim    = require'shim'
local mty     = require'metaty'
local civtest = require'civtest'
local ds      = require'ds'
local pth     = require'ds.path'
local fd      = require'fd'

local doc   = require'doc'
local ff    = require'ff'
local ele   = require'ele'
local astyle = require'asciicolor.style'
civtest.assertGlobals(initG)

local sfmt = string.format

if M == MAIN then
  local cmd = table.remove(arg, 1)
  if not cmd then print'Usage: civ.lua pkg ...'; os.exit(1) end
  require(cmd).main(shim.parse(arg))
end

return M

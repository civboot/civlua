#!/usr/bin/env -S lua -e "require'pkglib'()"
local G = G or _G

-- civ module: packaged dev environment
local M = G.mod'civ'; G.MAIN = G.MAIN or M
G.METATY_CHECK = true

local fmt = require'fmt'
local fd  = require'fd'
local ac  = require'asciicolor'
local acs = require'asciicolor.style'
local shim = require'shim'

--- create a Fmt with sensible defaults for scripts
--- Typically [$t.to] is unset (default=stderr) or set to stdout.
M.Fmt = function(t)
  t.to = t.to or io.stderr
  return acs.Fmt(t)
end

M.setupFmt = function(to, user)
  io.fmt  = M.Fmt{to=to}
  io.user = M.Fmt{to=user or io.stdout}
end

M.main = function(arg) --> int: return code
  M.setupFmt()
  local cmd = table.remove(arg, 1)
  if cmd == 'help' then
    cmd = assert(table.remove(arg, 1), 'Usage: help command')
    io.fmt:styled('bold', 'Help for command '..cmd, '\n')
    local mod = require(cmd)
    return require'doc'{rawget(mod, 'Main') or rawget(mod, 'main')}
  end
  if not cmd then
    io.fmt:styled('error', 'Usage: civ.lua pkg ...')
    return 1
  end
  require(cmd).main(shim.parse(arg))
end

if M == MAIN then os.exit(M.main(G.arg)) end
return M

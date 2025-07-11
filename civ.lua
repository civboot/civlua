#!/usr/bin/env -S lua
require'pkglib'(); local G = assert(G)

-- civ.lua: convieience command runner and environment config.
local M = G.mod'civ'; G.MAIN = G.MAIN or M
G.METATY_CHECK = true

local fmt = require'fmt'
local ds  = require'ds'
local fd  = require'fd'
local ac  = require'asciicolor'
local shim = require'shim'


--- create a Fmt with sensible defaults for scripts
--- Typically [$t.to] is unset (default=stderr) or set to stdout.
M.Fmt = function(t)
  t.to = t.to or io.stderr
  return ac.Fmt(t)
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
    local mod = ds.want(cmd)
    if not mod then
      io.fmt:styled('error', ('module %q not found.'):format(cmd), '\n')
      io.fmt:styled('notify', 'Did you mean "doc" instead of "help"?', '\n')
      return 1
    end
    io.fmt:styled('bold', 'Help for command '..cmd, '\n')
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

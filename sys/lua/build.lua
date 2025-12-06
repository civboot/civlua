#!/usr/bin/env -S lua
print'Running command:'
for i=0, 10 do
  if arg[i] == nil then break end
  print(' Arg', i, arg[i])
end

local mty  = require'metaty'

--- lua builder for civ.
local M = mty.mod'sys:lua.build'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local b = require'civ.Builder':get()
io.stderr:write'lua builder starting\n'

for _, id in ipairs(b.ids) do
  local tgt = b:target(id)
  io.stderr:write('lua building target: ', tgt:tgtname(), '\n')
  b:copyOut(tgt, 'lua')
  -- b:copyOut(tgt, 'data')
end

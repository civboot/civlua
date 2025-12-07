#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua builder for civ.
local M = mty.mod'sys:lua.build'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local b = require'civ.Builder':get()

for _, id in ipairs(b.ids) do
  local tgt = b:target(id)
  b:copyOut(tgt, 'lua')
  b:copyOut(tgt, 'data')
  b:link(tgt)
end

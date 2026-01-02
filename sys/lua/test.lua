#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua tester for civ.
local M = mty.mod'sys:lua.test'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local w = require'civ.Worker':get()
local pth = require'ds.path'
local ix = require'civix'
local info = require'ds.log'.info

for _, id in ipairs(w.ids) do
  info('testing id %q', id)
  local tgt = w:target(id)
  for _, src in pairs(tgt.src) do
    dofile(tgt.dir..src)
  end
end

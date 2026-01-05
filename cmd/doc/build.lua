#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua builder for civ.
local M = mty.mod'civ:cmd/doc/build.lua'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local info = require'ds.log'.info
local ix = require'civix'
local doc = require'doc'
local core = require'civ.core'

local push = ds.push
local w = require'civ.Worker':get()

local B = assert(w.cfg.buildDir)
local outp = {'out', 'doc', 'lua'}
local O = B..'doc/lua/'
ix.mkDirs(O)

local function build(id)
  local tgt = w:target(id)
  info('documenting %q', tgt:tgtname())

  local tgts = {}
  for _, depId in ipairs(tgt.depIds) do
    local tgt = w:target(depId)
    tgts[tgt:tgtname()] = tgt
  end

  local raw = {}
  for i, src in ipairs(tgt.src) do raw[i] = tgt.dir..src end

  local cmd = {
    raw = raw, expand=2,
    cmd = tgt.tag.cmd or nil,
    to  = O..ds.only(assert(ds.getp(tgt, outp))),
  }
  for _, modtgt in ipairs(tgt.extra.lua) do
    ds.extend(cmd, tgts[core.tgtname(modtgt)].api)
  end
  info('doc cmd: %q', cmd)
  doc(cmd)
end

for _, id in ipairs(w.ids) do build(id) end

#!/usr/bin/env -S lua
local mty  = require'metaty'

--- lua tester for civ.
local M = mty.mod'sys:lua.test'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local info = require'ds.log'.info
local push = require'ds'.push
local w = require'civ.Worker':get()

io.stderr:write('Running sys/lua/test.lua on '..#w.ids..' ids\n')

local function main()
  for _, id in ipairs(w.ids) do
    local tgt = w:target(id); if tgt.kind ~= 'test' then goto continue end
    info('testing %q', tgt:tgtname())
    for _, src in pairs(tgt.src) do
      dofile(tgt.dir..src)
    end
    ::continue::
  end
end

os.exit(ds.main(main))

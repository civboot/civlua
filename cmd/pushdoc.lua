#!/usr/bin/env -S lua
local mty = require'metaty'

--- Small script to build and push docs.
local M = mty.mod'pushdoc'
local G = mty.G; G.MAIN = G.MAIN or M

M.Main = mty'Main' {
  __cmd = 'pushdoc',
  'pat [string]: documentation pattern to push.', 
  'config [string]: path to civ.core.Config',
}

local ds = require'ds'
local core = require'civ.core'
local civ = require'civ'
local doc = require'doc'

function M.Main:call()
  local cv = core.Civ{cfg=core.Cfg:load(self.config)}
  local tgtnames = cf:expandAll(self)
  civ.build(cv, tgtnames)
  for _, tgtname in ipairs(tgtnames) do
    local tgt = cf:target(tgtname)
    local nameCxt = ds.only(tgt.out.doc.lua)
    doc{
      cv.cfg.buildDir..'out/lua/'..nameCxt,
      to='lua/'..assert(nameCxt:gsub('(%.cxt)$', '.html'))
      html = true,
    }
  end
end

if M == MAIN then return ds.main(shim.run, M.Main, shim.parse(arg)) end
getmetatable(M).__call = function(_, args)
  return M.Main(shim.parseStr(args))()
end
return P

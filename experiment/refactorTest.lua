#!/usr/bin/env -S lua -e "require'pkglib'()"

G.MAIN = {}
local R = require'ds'.R
local sfmt = string.format
local rd, wr = R.ds.readPath, R.ds.writePath

R.civ.setupFmt()
print('STARTING')

local function sub(name, ...)
  if name:find'%W' then return sfmt("\nT['%s'] = function()", name) end
  return sfmt('\nT.%s = function()', name)
end

for i, path in ipairs(arg) do
  print('!! path', path)
  local text = rd(path)
  text = text:gsub('\nT?%.?test%([\'"]([^\n]*)[\'"],[^\n]*', sub)
  text = text:gsub('\nend%)', '\nend')
  text = text:gsub('T?%.?assertEq', 'T.eq')
  wr(path, text)
end

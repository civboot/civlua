-- utools: small unix-like tools
local M = mod and mod'utools' or {}

local shim  = require'shim'
local mty   = require'metaty'
local ds    = require'ds'
local civix = require'civix'
local push = table.insert

M.List = mty'List'{'depth [int]', depth=1}
-- ls'path1 path2 --depth=3'
-- list paths
M.ls = function(args)
  args = shim.parse(args)
  local paths = civix.ls(args, args.depth)
  table.sort(paths); push(paths, '')
  io.write(table.concat(paths), '\n')
end

-- rm'path1 path2/ -r'
-- Remove. If -r is passed, remove recursively
M.rm = function(args)
  args = shim.parse(args)
  local rm = args.r and civix.rmRecursive or civix.rm
  for path in args do rm(path) end
end

M.sh = function(args)
end

return M

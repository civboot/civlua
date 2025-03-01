local G = G or _G
--------------------------------
-- Unix Version Control Functions
-- These shell out to unix for functionality instead of using civboot owned
-- algorithms.
local M = G.mod and mod'pvc.unix' or {}

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
M.diff = function(dir, a, b) --> string
  local aPath, bPath
  if not a then a, aPath = NULL, NULL
  else             aPath = pconcat{dir or './', a} end
  if not b then b, bPath = NULL, NULL
  else             bPath = pconcat{dir or './', b} end
  return ix.sh{
    'diff', '-N', aPath, '--label='..a, bPath, '--label='..b,
    unified='0', stderr=io.stderr}
end

local patchArgs = function(cwd, path)
  return {'patch', '-fu', input=path, CWD=cwd}
end

--- forward patch
M.patch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-N')
  return ix.sh(args)
end

--- reverse patch
M.rpatch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-R')
  return ix.sh(args)
end

--- incorporate all changes that went into going from base to change into to
M.merge = function(to, base, change)
  return ix.sh{'merge', to, base, change}
end

return M

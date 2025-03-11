local G = G or _G
--------------------------------
-- Unix Version Control Functions
-- These shell out to unix for functionality instead of using civboot owned
-- algorithms.
local M = G.mod and mod'pvc.unix' or {}

local ix = require'civix'
local pth = require'ds.path'

local push = table.insert
local trace = require'ds.log'.trace
local NULL = '/dev/null'

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
--- the [$l] variables are the "label" to use.
--- when the coresponding value is nil then the label is [$/dev/null]
M.diff = function(a,al, b,bl) --> string?
  if not a then a, al = NULL, NULL end
  if not b then b, bl = NULL, NULL end
  local o, e, sh = ix.sh{
    'diff', '-N', a, '--label='..al, b, '--label='..bl,
    unified='0', stderr=io.stderr, rc=true}
  if sh:rc() > 1 then error('diff failed:\n'..e) end
  if sh:rc() == 1 then return o end
  assert(o == '')
end

local patchArgs = function(cwd, path)
  return {'patch', '-fu', input=pth.abs(path), CWD=cwd}
end

--- forward patch
M.patch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-N')
  trace('sh%q', args)
  return ix.sh(args)
end

--- reverse patch
M.rpatch = function(cwd, path)
  local args = patchArgs(cwd, path); push(args, '-R')
  trace('sh%q', args)
  return ix.sh(args)
end

--- incorporate all changes that went into going from base to change into to
M.merge = function(to, base, change) --> ok, err
  assert(to, 'must provide to')
  base, change = base or NULL, change or NULL
  trace('merging t:%s b:%s c:%s', to, base, change)
  local o, e, sh = ix.sh{'merge', '-A', to, base, change, rc=true}
  trace('merge rc=%i', sh:rc())
  if sh:rc() == 0 then return true end
  return nil, e
end

return M

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

local EMPTY_DIFF = [[
--- %s
+++ %s
@@ -0,0 +0,1 @@
+
]]

local diffCheckPath = function(p, pl) --> p, pl
  if not p then return NULL, NULL end
  if ix.stat(p):size() == 0 then error(
    p..' has a size of 0, which patch cannot handle'
  )end
  return p, pl
end

--- Get the unified diff using unix [$diff --unified=1],
--- properly handling file creation/deleting
--- the [$l] variables are the "label" to use.
--- when the coresponding value is nil then the label is [$/dev/null]
M.diff = function(a,al, b,bl) --> string?
  a, al = diffCheckPath(a, al)
  b, bl = diffCheckPath(b, bl)
  local o, e, sh = ix.sh{
    'diff', '-N', a, '--label='..al, b, '--label='..bl,
    unified='0', stderr=io.stderr, rc=true}
  trace('diff rc=%i', sh:rc())
  if sh:rc() > 1 then error('diff failed:\n'..e) end
  if sh:rc() == 1 then
    return o
  end
  error((a or b)..' is empty (https://stackoverflow.com/questions/44427545)')
end

local patchArgs = function(cwd, path)
  return {'patch', '-p0', '-fu', input=pth.abs(path), CWD=cwd}
end

--- forward patch
M.patch = function(cwd, path)
  cwd = pth.toDir(cwd)
  local args = patchArgs(cwd, path); push(args, '-N')
  trace('sh%q', args)
  return ix.sh(args) or ''
end

--- reverse patch
M.rpatch = function(cwd, path)
  cwd = pth.toDir(cwd)
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

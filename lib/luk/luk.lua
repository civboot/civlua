local mty = require'metaty'

--- luk: lua config language.
local M = mty.mod'luk'

local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local dload = require'ds.load'

local push, pop = ds.push, table.remove

M.ENV = dload.ENV

function M.checkCycle(cycle, path)
  if cycle[path] then
    push(cycle, path)
    error('cycle detected:\n  '
      ..table.concat(ds.slice(cycle, ds.indexOf(path)), '\n  '))
  end
end

--- The luk loader.
M.Luk = mty'Luk' {
  'imported {string: pod}: table of ipath -> imported luk',
  'imports {string: {string}}: table of ipath to its imports for dependency analysis.',
 [[pathFn [fn(string) -> string]: a function that given a non-relative import path
     returns the path to the file to import.]],
   pathFn = ds.iden,
  'envMeta', envMeta=dload.ENV,
  'cycle {path}: used to detect cycles',
}
getmetatable(M.Luk).__call = function(T, t)
  t.imported = t.imported or {}
  t.imports  = t.imports  or {}
  t.cycle    = t.cycle    or {}
  return mty.construct(T, t)
end

--- Resolve the path into the abspath.
function M.Luk:resolve(path, wd) --> /abs/path
  if path:find'^/'      then return path end
  if path:find'^%.%.?/' then return pth.abs(path, wd) end
  return pth.abs(self.pathFn(path))
end

--- Recursively import the luk file at path.
--- Each luk file has a sandboxed global environment.
function M.Luk:import(path, wd) --> luk, abspath
  path = self:resolve(path, wd)
  local lk = self.imported[path]; if lk then return lk end
  info('luk loading: %q', path)
  M.checkCycle(self.cycle, path)
  push(self.cycle, path); self.cycle[path] = 1
  self.imports[path] = {}
  local pathWd, env = pth.dir(path), {}
  env.import = function(p)
    local luk, ap = self:import(p, pathWd)
    push(self.imports[path], ap)
    return luk
  end
  local ok, luk = dload(path, env, self.envMeta)
  if not ok then error(tostring(luk)) end -- FIXME
  self.imported[path] = luk
  assert(pop(self.cycle) == path); self.cycle[path] = nil
  return luk
end

return M

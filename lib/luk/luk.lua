local mty = require'metaty'

--- luk: lua config language.
local M = mty.mod'luk'

local fmt = require'fmt'
local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local dload = require'ds.load'

local assertf = fmt.assertf
local push, pop = ds.push, table.remove
local getmt = getmetatable

M.ENV = dload.ENV

function M.checkCycle(cycle, path)
  if cycle[path] then
    push(cycle, path)
    error('cycle detected:\n  '
      ..table.concat(ds.slice(cycle, ds.indexOf(path)), '\n  '))
  end
end

--- A luk table object
M.Table = mty'Table' {}
getmt(M.Table).__call = function(T, self)
  for k, v in pairs(self) do
    v = M.value(v); self[k] = v
    if k == '__call' then
      assert(mty.callable(v), '__call must be callable')
    end
  end
  return setmetatable(self, T)
end
function M.Table:__call(...)
  return assert(rawget(self, '__call'),
                'attempt to call luck table which has no __call set')(...)
end
M.Table.__newindex = nil
getmt(M.Table).__index = nil
M.Table.__fmt = fmt.table

--- Convert value to luk-value
function M.value(v)
  return type(v) == 'table' and not getmt(v) and M.Table(v)
      or v
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
getmt(M.Luk).__call = function(T, t)
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
function M.Luk:import(path, wd) --> lukMod?, ds.Error?
  path = self:resolve(path, wd)
  local lk = self.imported[path]; if lk then return lk end
  info('loading luk: %q', path)
  M.checkCycle(self.cycle, path)
  push(self.cycle, path); self.cycle[path] = 1
  self.imports[path] = {}
  local pathWd, env = pth.dir(path), {}
  env.import = function(p)
    assertf(type(p) == 'string', 'import expects string, got: %q', p)
    return assert(self:import(p, pathWd))
  end
  local ok, luk = dload(path, env, self.envMeta)
  if not ok then return nil, --[[error]]luk end
  luk = assertf(M.value(luk), '%s did not return a value', path)
  self.imported[path] = luk
  assert(pop(self.cycle) == path); self.cycle[path] = nil
  return luk
end

return M

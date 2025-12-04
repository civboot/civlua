local mty = require'metaty'

--- luk: lua config language.
local M = mty.mod'luk'

local ds = require'ds'
local dload = require'ds.load'

local IMPORT_CALLED = '__IMPORT CALLED__'

--- The luk loader.
M.Luk = mty'Luk' {
  'preLuks {string: pod}: table of ipath -> preloaded luk',
  'luks {string: pod}: table of ipath -> loaded luk',
  'imports {string: {string}}: table of ipath to its imports',
 [[pathFn [fn(string) -> string]: a function that given an ipath
     returns the path to the file to load.]],
   pathFn = ds.iden,
}

function M.Luk:preload(ipath)
  local p = self.pathFn(ipath)
  local l = self.luks[p] or self.preLuks[p]
  if l then return l end
  l = M.preload(p)
end

function M.getimports(path, env, ENV, reserved) --> import?, errmsg?
  env = env or {}
  ENV = ENV or dload.ENV
  local import

  env.import = function(i) import = i; error(IMPORT_CALLED) end
  local ok, res = dload(path, env, ENV)
  if ok then return {} end
  if not res.msg:find(PKG_CALLED) then error(tostring(res)) end
  return import
end


M.load = function(root, relpath, env, ENV)

  local ok, res = dload(path, env, ENV)
  if ok then error(path..' never called pkg{...}') end
  if not res.msg:find(PKG_CALLED) then error(tostring(res)) end
  P.import = P.import or {}
  for k, v in pairs(P.import) do
    if type(k) ~= 'string' or type(v) ~= 'string' then
      error'import must be map of str -> str'
    end
    fmt.assertf(not M.RESERVED[v], 'import name reserved: %s', v)
  end

end

return M

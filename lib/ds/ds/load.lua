local mty = require'metaty'

--- load lua modules with custom or default environment in a sandboxed
--- environment. This is extremely useful for configurations written in lua or
--- writing your own config-like language.
---
--- The default environment (ds.load.ENV) has safe default functions which
--- cannot access state and missing unsafe functions like getmetatable or the
--- debug module.
---
--- [{:h2}loading]
--- To perform the load, call this module with:
--- [##
---   (path, env={}, envMeta=ds.load.ENV) -> ok, result
--- ]##
--- inputs: [+
--- * path: path to load (lua-syntax file).
--- * env: global environment.
--- * envMeta: metatable of global environment. If env
---   already has a metatable this is ignored.
--- ]
---
--- outputs: [+
--- * ok: boolean to indicate load success or failure of script.
--- * result: result or loading or ds.Error.
--- ]
---
--- Throws an error if the path is not valid lua code.
local M = mty.mod'ds.load'

local ds = require'ds'

local getmt, setmt = getmetatable, setmetatable
local sfmt = string.format

--- Default environment for sandboxed loading.
M.ENV = {
  __name = 'ds.load.ENV',
  format=string.format,
  insert=table.insert, sort=table.sort, concat=table.concat,
  update=ds.update, merge=ds.merge,

  pairs=pairs,   ipairs=ipairs,
  error=error,   assert=assert,
}; M.ENV.__index = M.ENV

--- Similar to lua's [$loadfile] but follows conventions of [$ds.load(...)].
--- Unlike loadfile, this throws an error if the path doesn't parse.
M.loadfile = function(path, env, envMeta) --> fn
  env = env or {}
  if not getmt(env) then setmt(env, envMeta or M.ENV) end
  local m, err = loadfile(path, nil, env)
  if err then error(sfmt('failed to parse %s: %s', path, err)) end
  return m
end

getmetatable(M).__call = function(_, path, env, envMeta) --> ok, result
  return ds.try(M.loadfile(path, env, envMeta))
end
return M

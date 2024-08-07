local M = mod'ele.types'

local mty    = require'metaty'
local ds     = require'ds'
M.term       = require'vt100'
local sfmt = string.format
local push, pop, concat = table.insert, table.remove, table.concat
local get = ds.get

M.ID = 1
M.uniqueId = function()
  local id = M.ID; M.ID = M.ID+1; return id
end

M.checkBinding = function(b)
  if not mty.callable(b) then
    return 'binding must be callable'
  end
end

M.checkBindings = function(btable, path)
  path = path or {}; push(path, '<root>')
  if type(btable) ~= 'table' then error(sfmt(
    '%s: bindings must be only tables and callables', concat(path)
  ))end

  local keyError, err = M.term.keyError
  for k, b in pairs(btable) do
    path[#path] = k
    if k == 'fallback' then
      if not mty.callable(b) then error(sfmt(
        '%s: fallback must be callable', concat(path)
      ))end
      goto continue
    end
    err = (type(k) ~= 'string') and 'keys must be str' or keyError(k)
    if err then return sfmt('%s: %s', concat(path, ' '), err) end
    if not mty.callable(b) then
      M.checkBindings(b, path)
    end
    ::continue::
  end
  pop(path)
end

M.checkMode = function(data, mode) --> errstring
  if not data.modes[mode] then
    return sfmt('modes.%s does not exist', mode)
  end
end

M.checkAction = function(data, action) --> errstring
  if not mty.callable(get(data, {'actions', action})) then
    return sfmt('actions.%s is not a callable', action)
  end
end

return M

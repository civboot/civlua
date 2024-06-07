local M = mod'ele.types'
M.term = require'civix.term' -- can replace

local ds = require'ds'

local sfmt = string.format
local push, pop = table.insert, table.remove
local get = ds.get

M.ID = 1
M.uniqueId = function()
  local id = M.ID; M.ID = M.ID+1; return id
end

M.checkBinding = function(data, b)
  if not get(data, {'bindings', b}) then
    return sfmt('bindings.%s does not exist', b)
  end
end

M.checkBindings = function(data, btable, path)
  path = path or {}; push(path, '<replace>')
  local keyError, err = M.term.keyError
  for k, b in pairs(btable) do
    path[#path] = k
    if k == 'fallback' then
      err = M.checkBinding(data, b)
      if err then return sfmt('%s: %s', concat(path, ' '), err) end
      goto continue
    end
    err = keyError(k); if err then return sfmt(
      '%s: %s', concat(path, ' '), err
    )end
    if type(b) == 'table' then M.checkBindings(data, b, path)
    else
      err = M.checkBinding(data, b)
      if err then return sfmt('%s: %s', concat(path, ' '), err) end
    end
    ::continue::
  end
  pop(path)
end

M.checkMode = function(data, mode) --> errstring
  if not get(data, {'bindings', 'modes', mode}) then
    return sfmt('bindings.modes.%s does not exist', mode)
  end
end

M.checkAction = function(data, action) --> errstring
  if type(get(data, {'actions', action})) ~= 'function' then
    return sfmt('actions.%s is not a function', action)
  end
end


return M

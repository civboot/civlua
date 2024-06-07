local M = mod'ele.types'
M.term = require'civix.term' -- can replace

local ds = require'ds'

local sfmt = string.format
local get = ds.get

M.ID = 1
M.uniqueId = function()
  local id = M.ID; M.ID = M.ID+1; return id
end

M.checkBinding = function(ele, b)
  if not get(ele, {'bindings', b}) then
    return sfmt('bindings.%s does not exist', b)
  end
end

M.checkBindings = function(ele, btable, path)
  path = path or {}; push(path, '<replace>')
  local keyError, err = M.term.keyError
  for k, b in pairs(btable) do
    path[#path] = k
    if k == 'fallback' then
      err = et.checkBinding(ele, b)
      if err then return sfmt('%s: %s', concat(path, ' '), err) end
      goto continue
    end
    err = keyError(k); if err then return sfmt(
      '%s: %s', concat(path, ' '), err
    )end
    if type(b) == 'table' then M.checkBindings(ele, b, path)
    else
      err = et.checkBinding(ele, b)
      if err then return sfmt('%s: %s', concat(path, ' '), err) end
    end
    ::continue::
  end
  pop(path)
end

M.checkMode = function(ele, mode) --> errstring
  if not get(ele, {'bindings', 'mode', mode}) then
    return sfmt('bindings.mode.%s does not exist', mode)
  end
end

M.checkAction = function(ele, action) --> errstring
  if type(get(ele, {'actions', action})) ~= 'function' then
    return sfmt('actions.%s is not a function', action)
  end
end


return M

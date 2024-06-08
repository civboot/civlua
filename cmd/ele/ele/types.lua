local M = mod'ele.types'

local mty = require'metaty'
local ds  = require'ds'
M.term    = require'civix.term' -- can replace

local sfmt = string.format
local push, pop = table.insert, table.remove
local get = ds.get

M.ID = 1
M.uniqueId = function()
  local id = M.ID; M.ID = M.ID+1; return id
end

-- Data is the global state that actions have access to.
-- Any field can be assigned to, this record is just for documentation
-- purposes.
--
-- action signature: function(data, event, evsend)
M.Data = mty'Data' {
  'resources [table]: table of resources to close when shutting down',
  'keys     [Keys]:  see bindings.lua',
  'bindings [table]: see bindings.lua',
  'view [RootView]: the root view',
  'edit [Buffer]: the current edit buffer',
  'run [boolean]: set to false to stop the app', run=true,
}
M.Data.__newindex = nil
getmetatable(M.Data).__index = nil

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

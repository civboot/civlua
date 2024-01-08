
local mty = require'metaty'

local M = {}

M.Keep = mty.record'patch.Keep':field('num',  'number')
M.Chng = mty.record'patch.Chng'
  :field('rem', 'number')     :fdoc'number of lines to remove'
  :fieldMaybe'add':fdoc'text to add'

return M

---------------------
-- DateTime: a year, day and time
local pkg = require'pkg'
local mty = pkg'metaty'

local M = {}

M.DAY_SECONDS = 24 * 60 * 60
M.MONTH_DAYS = {
-- jan feb mar apr may jun
   31, 28, 31, 30, 31, 30,
-- jul aug sep oct nov dec
   31, 31, 30, 31, 30, 31,
}
M.MONTH_SHORT = {
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
}

M.DateTime = record'DateTime'
  :field'year'
  :field'yearSeconds':fdoc'seconds into year'
  :fieldMaybe'ns'    :fdoc'nanoseconds into second'

M.DateTime.isLeapYear = function(dt) return 0 == dt.year % 4 end
M.DateTime.dayOfYear = mty.doc'Get the day of the year [0-366]'
(function(dt) return math.floor(dt.yearSeconds / DAY_SECONDS) end)

M.DateTime.month = function(dt)
end

return M

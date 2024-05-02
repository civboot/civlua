---------------------
-- DateTime: a year, day and time
local mty = require'metaty'

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

M.DateTime = record2'DateTime' {
  'year[int]',
  'yearSeconds[int]  seconds into year',
  'ns[int]           nanoseconds into second',
}
M.DateTime.isLeapYear = function(dt) return 0 == dt.year % 4 end
-- Get the day of the year [0-366]
M.DateTime.dayOfYear =
(function(dt) return math.floor(dt.yearSeconds / DAY_SECONDS) end)

M.DateTime.month = function(dt)
end

return M

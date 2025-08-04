local mty = require'metaty'

--- A lines table with a write method and a few other file-like methods.
---
--- This is NOT performant, especially for small writes or large lines. It is
--- useful for tests and cases where simplicity is more important than
--- performance.
local Writer = mty'lines.Writer' {}

local ds = require'ds'
local lines = require'lines'

getmetatable(Writer).__index = mty.hardIndex
Writer.__newindex            = mty.hardNewindex
Writer.set = rawset
Writer.get = rawget
Writer.write = lines.write
Writer.flush = ds.noop
Writer.extend = ds.defaultExtend
Writer.icopy  = ds.defaultICopy

return Writer

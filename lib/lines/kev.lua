local mty = require'metaty'

--- kev: "Key Equal Value" serialization format.
---
--- This is an extremely common format in many unix utilities, "good enough"
--- for a large number of configuration use cases. The format is simple: a file
--- containing lines of [$key=value]. The input and output are a table of
--- key,val strings (though tostring is called for [$to()]). Lines which start
--- with [$#] or don't have [$=] in them are ignored.
---
--- Nested data is absolutely not supported. Spaces are treated as literal both
--- before and after [$=]. If you want a key containing [$=] or key/value
--- containing newline then use a different format (or write your own).
local M = mty.mod'lines.kev'

local lines = require'lines'
local split = require'ds'.split
local sconcat = string.concat
local push = table.insert
local concat, sort = table.concat, table.sort
local sfmt, find = string.format, string.find

--- convert to a table of [$key=value] lines.
function M.to(t)
  local kv = {}; for k, v in pairs(t) do
    push(kv, sconcat('=', tostring(k), tostring(v)))
  end
  sort(kv)
  return kv
end

--- convert [$key=value] lines to a table.
function M.from(lines, to)
  to = to or {}
  for _, line in ipairs(lines) do
    local i = not (line:sub(1,1)=='#') and find(line, '=')
    if i then
      to[line:sub(1, i-1)] = line:sub(i+1)
    end
  end
  return to
end

function M.load(f, to) return M.from(lines.load(f), to) end
function M.dump(t, f)  return lines.dump(M.to(t), f)    end

return M

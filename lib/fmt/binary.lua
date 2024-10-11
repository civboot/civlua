local G = G or _G

--- format binary text
local M = G.mod and mod'fmt.binary' or setmetatable({}, {})
G.MAIN = G.MAIN or M

local mty = require'metaty'
local shim = require'shim'
require'fmt' -- sets io.fmt

local byte, srep, sfmt = string.byte, string.rep, string.format
local min = math.min

local FMT = '%.2x '

--- Command: [${'path.bin', width=16, '--', 'literal binary'}]
--- Use [$-] to also format stdin
M.Args = mty'Args' {
  'width [int]: column width in bytes',  width=16,
  'fmt [string]: format string for hex', fmt=FMT,
}

local read = function(path)
  local f = assert(io.open(path))
  local s = assert(f:read'a'); f:close()
  return s
end

M.format = function(f, str, fmt)
  fmt = fmt or FMT
  local b
  for i=1,#str do
    b = byte(str, i,i)
    if 32 <= b and b <= 127 then f:write(sfmt(fmt, b))
    else f:styled('literal', sfmt(fmt, b)) end
  end
  f:write''
end
local format = M.format

M.columns = function(f, str, fmt, width)
  fmt, width = fmt or FMT, width or 16
  local i, len = 1, #str
  while i <= len do
    local s = str:sub(i, i+width)
    if i ~= 1 then f:write'\n' end
    format(f, s, fmt)
    f:styled('meta', ' | ');
    for c=i,min(i+width-1, len) do
      local b = byte(str,c,c)
      if 32 <= b and b <= 127 then f:write(str:sub(c,c))
      else f:styled('empty', ' ') end
    end
    i = i + width
  end
end
local columns = M.columns

M.main = function(args)
  args = M.Args(shim.parseStr(args))
  local raw = shim.popRaw(args)
  local f, fmt, width = io.fmt, args.fmt, args.width
  for _, path in ipairs(args) do
    columns(f, (path=='-') and io.stdin:read() or read(path), fmt, width)
  end
  if raw then
    for _, r in ipairs(raw) do columns(f, r, fmt, width) end
  end
  f:write'\n'
end
local main = M.main

if M == MAIN then os.exit(main(shim.parse(G.arg))) end
getmetatable(M).__call = function(_, args) return main(args) end
return M

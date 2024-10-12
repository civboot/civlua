local G = G or _G

--- format binary text
--- When called directly returns the result of
--- [$binary.columns(fmt.Fmt{}, ...)]
local M = G.mod and mod'fmt.binary' or setmetatable({}, {})
G.MAIN = G.MAIN or M

local mty = require'metaty'
local shim = require'shim'
local Fmt = require'fmt'.Fmt

local concat = table.concat
local byte, srep, sfmt = string.byte, string.rep, string.format
local min = math.min

local FMT = '%.2x '

--- Command: [${'path.bin', width=16, '--', 'literal binary'}]
--- Use [$-] to format stdin
M.Args = mty'Args' {
  'width [int]: column width in bytes',  width=16,
  'fmt [string]: format string for hex', fmt=FMT,
  'to [file]: (lua only) file to output to (default=stdout)',
  'i [int]: starting index to use', i=0,
}

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

M.ascii = function(f, str)
  for c=1,#str do
    local b = byte(str,c,c)
    if 32 <= b and b <= 127 then f:write(str:sub(c,c))
    else f:styled('empty', ' ') end
  end
end
local ascii = M.ascii

local formatCols = function(f, str, fmt, offset)
  f:styled('line', sfmt('% 6i: ', offset));
  format(f, str, fmt)
end

M.columns = function(f, str, width, si, fmt)
  fmt, width, si = fmt or FMT, width or 16, si or 0
  local i, len, s = 1, #str
  if len == 0 then return end
  if len <= width then goto last end -- only 1 line
  -- first line
  s = str:sub(i, i+width-1)
  formatCols(f, s, fmt, i+si-1); f:styled('meta', ' | '); ascii(f, s)
  i = i + width
  while i <= len-width do -- middle lines
    s = str:sub(i, i+width-1); f:write'\n'
    formatCols(f, s, fmt, i+si-1); f:styled('meta', ' | '); ascii(f, s)
    i = i + width
  end
  ::last::
  if i <= len then -- last line (with padding)
    if len > width then f:write'\n' end
    s = str:sub(i)
    formatCols(f, s, fmt, i+si-1)
    f:write(srep(' ', #sfmt(fmt, 1) * (width - #s)))
    f:styled('meta', ' | '); ascii(f, s)
  end
  return f
end
local columns = M.columns

getmetatable(M).__call = function(_, ...) return concat(columns(Fmt{}, ...)) end

M.main = function(args)
  args = M.Args(shim.parseStr(args))
  local raw = shim.popRaw(args)
  local fmt, width, si = args.fmt, args.width, args.i
  local f = require'civ'.Fmt{to=args.to or io.stdout}
  local read = require'ds'.readPath
  for _, path in ipairs(args) do
    columns(f, (path=='-') and io.stdin:read'a' or read(path), width, si, fmt)
  end
  if #args > 0 then f:write'\n' end
  if raw then
    for _, r in ipairs(raw) do columns(f, r, width, si, fmt) f:write'\n' end
  end
end
local main = M.main

if M == MAIN then os.exit(main(shim.parse(G.arg))) end
return M

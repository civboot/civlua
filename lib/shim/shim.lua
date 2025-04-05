--- shim: use a lua module in lua OR in the shell.
local M = mod and mod'shim' or setmetatable({}, {})

local push, sfmt = table.insert, string.format
local lower = string.lower

local ENV_VALS = {['true'] = true, ['1'] = true }

--- Parse either a string or list and convert them to key=value table.
--- v can be either a list of [${'strings', '--option=foo'}]
--- or [${'strings", option='foo'}] or a combination of both. If v is a string then
--- it is split on whitespace and parsed as a list.
---
--- Note: this handles repeat keys by creating and appending a list for that key.
M.parse = function(v) --> args
  if type(v) == 'string' then return M.parseStr(v)
  else                        return M.parseList(v) end
end

--- Add k,v to table, turning into a list if it already exists.
local function addKV(t, k, v)
  local e = t[k]; if e then
    if type(e) == 'table' then push(e, v)
    else t[k] = {e, v} end
  else t[k] = v end
end

--- parses the string by splitting via whitespace.
--- Asserts the string contains no special chars: [$'"[]]
--- This is for convinience, use a table if it's not enough.
---
--- Note: if the input is already a table it just returns it.
M.parseStr = function(str) --> args
  str = str or {}
  if type(str) == 'table' then return str end
  if str:find'[%[%]\'"]' then error(
    [[parseStr does not support chars '"[]: ]]..str
  )end
  local args = {}; for a in str:gmatch'%S+' do push(args, a) end
  return M.parseList(args)
end

--- Note: typically use parse() or parseStr() instead.
M.parseList = function(strlist) --> args
  local t = {}; for i, arg in ipairs(strlist) do
    if arg == '--' then -- lone '--' indicates special parsing
      table.move(strlist, i, #strlist, #t+1, t)
      break
    elseif arg:find'^%-%-[^-]+' then
      local k, v = arg:match('(.-)=(.*)', 3)
      if k then addKV(t, k, v)
      else      addKV(t, arg:sub(3), true) end
    else        push(t, arg) end
  end
  return t
end

--- Helper for dealing with [$-s --short] arguments. Mutates
--- args to convert short paramaters to their long counterpart.
M.short = function(args, short, long, value) --> nil
  if args[short] then args[long] = value; args[short] = nil end
end

local BOOLS = {
  [true]=true,   ['true']=true,   ['yes']=true, ['1']=true,
  [false]=false, ['false']=false, ['no']=false, ['0']=false,
}

--- Duck type: always return a boolean (except for nil).
--- See BOOLS (above) for mapping.
M.boolean = function(v)
  if v == nil then return nil end
  local b = BOOLS[v] if b ~= nil then return b end
  error('invalid boolean: '..tostring(v))
end
M.bools = function(args, ...)
  for _, arg in ipairs{...} do
    args[arg] = M.boolean(args[arg])
  end
end

--- Duck type: always return a number
M.number = function(num)
  if num == nil then return nil end
  return (type(num)=='number') and num or tonumber(num)
end

local TOSTR = {
  ['nil'] = '', boolean = tostring, number = tostring,
  string = tostring,
}
--- Duck type: always return a string
--- This is useful for some APIs where you want to convert
--- number/true/false to strings
--- Converts nil to ''
M.string = function(v)
  local f = TOSTR[type(v)]; if f then return f(v) end
  error('invalid type for shim.string: '..type(v))
end

-- Duck type: always return a list.
-- default controls val==nil
-- empty   controls val==''
M.list = function(val, default, empty)
  if val == nil then val = default or {} end
  if empty and val == '' then return empty end
  return (type(val) == 'table') and val or {val}
end

--- Duck type: if val is a string then splits it
--- if it's a list leaves alone.
M.listSplit = function(val, sep)
  if val == nil then return {} end
  if type(val) == 'table' then return val end
  sep = '[^'..(sep or '%s')..']+'
  local t = {}; for m in val:gmatch(sep) do push(t, m) end
  return t
end

--- Duck type: get a file handle.
--- If [$v or default] is a string then open the file in mode [$default='w+']
M.file = function(v, default, mode--[[w+]]) --> file, error?
  v = v or default
  if type(v) == 'string' then return io.open(v, mode or 'w+') end
  return v
end

--- expand string keys into [$--key=value], ordered alphabetically.
--- This is mostly useful for interfacing with non-lua shells.
M.expand = function(args)
  local out, keys = {}, {}
  for k, v in pairs(args) do
    if type(k) == 'number'     then out[k] = M.string(v)
    elseif type(k) == 'string' then push(keys, k)
    else error('non string key: '..k) end
  end
  table.sort(keys); for _, k in ipairs(keys) do 
    push(out, sfmt('--%s=%s', k, M.string(args[k])))
  end
  return out
end


-- return nil if env var does not exist, else boolean (true for 'true' or '1')
M.getEnvBool = function(k)
  local v = os.getenv(k); if not v then return v end
  return ENV_VALS[lower(v)] or false
end

--- pop raw arguments after '--'
--- Removes them (including '--') from args.
M.popRaw = function(args, to) --> to
  local ri; for i, v in ipairs(args) do
    if v == '--' then ri = i; break end
  end; if not ri then return end
  local to = to or {}
  local raw = table.move(args, ri+1, #args, #to+1, to)
  for i=ri,#args do args[i] = nil end -- clear from args
  return to
end

--- Performs common setup by parsing and constructing an Args metaty, getting
--- the standard `to` attribute and checking help and printing to [$to] if
--- requested.
---
--- Returns the constructed Args and Styler.
---
--- [" Note: This method depends on the [$doc] module]
M.setup = function(Args, args) --> args, styler
  args = Args(M.parseStr(args))
  local to = M.file(args.to, io.stdout)
  local styler = require'asciicolor'.Styler{
    f = to, color = M.color(args.color, require'fd'.isatty(to)),
  }
  if args.help then M.styleHelp(styler, Args) end
  return args, styler
end

return M

-- shim: use a lua module in lua OR in the shell.
local M = mod and mod'shim' or setmetatable({}, {})

local push, sfmt = table.insert, string.format
local lower = string.lower

local ENV_VALS = {['true'] = true, ['1'] = true }

------------------
-- REMOVE: remove these

-- return nil if DNE, else boolean
M.getEnvBool = function(k)
  local v = os.getenv(k); if not v then return v end
  return ENV_VALS[lower(v)] or false
end

-- return whether the script has been executed directly
-- depth should be incremented for each function this is
-- called inside of.
-- stackoverflow.com/questions/49375638
M.isExe = function(depth)
  return _G.arg and not pcall(debug.getlocal, 5 + (depth or 0), 1)
end
assert(not M.isExe(), "Don't call shim directly")

local function invalid(msg)
  io.stderr:write(msg); io.stderr:write'\n'
  io.stderr:write(DOC)
  os.exit(1)
end

local function checkHelp(sh, args)
  if args.help == true and sh.help then
    local h = {sh.help}
    if sh.subs then
      push(h, '[{h2}Subcommands:]')
      local t = {}; for k in pairs(sh.subs) do table.insert(t, k) end
      table.sort(t)
      for _, s in ipairs(t) do push(h, '  '..s) end
    end
    require'cxt.term'{table.concat(h, '\n')}
    os.exit(0)
  end
end

local function shimcall(sh)
  local args = M.parse(_G.arg)
  ::loop::
  if sh.exe then
    checkHelp(sh, args)
    return sh.exe(args, true)
  end
  local sub = args[1] and sh.subs[args[1]]; if not sub then
    print('?? missing sub', sh)
    checkHelp(sh, args)
    invalid('Missing or unknown subcommand, use --help for usage')
  end
  sh = sub; table.remove(args, 1)
  goto loop
end

getmetatable(M).__call = function(ty_, sh)
  if rawget(sh, 'exe') and rawget(sh, 'subs') then error(
    'must specify exe OR subs, not both'
  )end
  if not (sh.exe or sh.subs) then error(
    'must specify one of: exe, subs'
  )end
  if _G.arg and M.isExe(1) then
    shimcall(sh)
    os.exit(0)
  end
  local mt = getmetatable(sh) or setmetatable(sh, {__name='SHIM'})
  mt.__call=shimcall
  return sh
end

--------------------------
-- KEEP

-- Parse either a string or list and convert them to key=value table.
-- v can be either a list of [${'strings', '--option=foo'}]
-- or [${'strings", option='foo'}] or a combination of both. If v is a string then
-- it is split on whitespace and parsed as a list.
M.parse = function(v) --> args
  if type(v) == 'string' then return M.parseStr(v)
  else                        return M.parseList(v) end
end

-- Add k,v to table, turning into a list if it already exists.
local function addKV(t, k, v)
  local e = t[k]; if e then
    if type(e) == 'table' then push(e, v)
    else t[k] = {e, v} end
  else t[k] = v end
end

M.parseList = function(strlist) --> args
  local t = {}; for i, arg in ipairs(strlist) do
    if arg:find'^%-%w+' then
      for c in arg:sub(2):gmatch('.') do
        addKV(t, c, true)
      end
    elseif arg:find'^%-%-[^-]+' then
      local k, v = arg:match('(.-)=(.*)', 3)
      if k then addKV(t, k, v)
      else      addKV(t, arg:sub(3), true) end
    else        push(t, arg) end
  end
  return t
end

-- parses the string by splitting via whitespace.
-- Asserts the string contains no special chars: '"[]
-- This is for convinience, use a table if it's not enough.
--
-- Note: if the input is already a table it just returns it.
M.parseStr = function(str) --> args
  if type(str) == 'table' then return str end
  if str:find'[%[%]\'"]' then error(
    [[parseStr does not support chars '"[]: ]]..str
  )end
  local args = {}; for a in str:gmatch'%S+' do push(args, a) end
  return M.parseList(args)
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

-- Duck type: always return a boolean (except for nil).
-- See BOOLS (above) for mapping.
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

-- Duck type: always return a number
M.number = function(num)
  if num == nil then return nil end
  return (type(num)=='number') and num or tonumber(num)
end

local TOSTR = {
  ['nil'] = '', boolean = tostring, number = tostring,
  string = tostring,
}
-- Duck type: always return a string
-- This is useful for some APIs where you want to convert
-- number/true/false to strings
-- Converts nil to ''
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

-- Duck type: if val is a string then splits it
-- if it's a list leaves alone.
M.listSplit = function(val, sep)
  if val == nil then return {} end
  if type(val) == 'table' then return val end
  sep = '[^'..(sep or '%s')..']+'
  local t = {}; for m in val:gmatch(sep) do push(t, m) end
  return t
end

-- expand string keys into [$--key=value], ordered alphabetically.
-- This is mostly useful for interfacing with non-lua shells.
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


-- Duck type: if value does not have a metatable then call T(val)
-- Note: strings DO have a metatable.
--
-- This is primarily used for types which have a __call constructor,
-- such as metaty types.
M.new = function(T, val)
  if val == nil then return end
  return getmetatable(val) and val or T(val)
end

local COLOR_YES = {[true]=1,  ['true']=1,  always=1, on=1}
local COLOR_NO  = {[false]=1, ['false']=1, never=1,  off=1}
-- return whether to use color based on your --color= arg and
-- isatty (see fd.lua to get)
--
-- https://bixense.com/clicolors/
M.color = function(color, isatty) --> useColor[bool], error
  local err
  if color ~= nil then
    if COLOR_YES[color] then return true end
    if COLOR_NO[color]  then return false end
    if color ~= 'auto' then
      err = 'invalid --color='..color
    end
  end
  if M.getEnvBool'NO_COLOR'       then return false, err end
  if M.getEnvBool'CLICOLOR_FORCE' then return true,  err end
  return M.getEnvBool'CLICOLOR' and isatty, err
end

--- Duck type: get a file handle.
--- If [$v or default] is a string then open the file in mode [$default='w+']
M.file = function(v, default, mode--[[w+]]) --> file, error?
  v = v or default
  if type(v) == 'string' then return io.open(v, mode or 'w+') end
  return v
end

--- If args.help is true write help to [$to]
M.checkHelp = function(args, to, color) --> gaveHelp
  if M.boolean(args.help) then
    require'cxt.term'{require'doc'.docstr(getmetatable(args)), to=to, color=color}
    return true
  end
end

return M

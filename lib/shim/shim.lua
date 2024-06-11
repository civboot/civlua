local push, sfmt = table.insert, string.format
local M = {}

local function addKV(t, k, v)
  local e = t[k]; if e then
    if type(e) == 'table' then push(e, v)
    else t[k] = {e, v} end
  else t[k] = v end
end

-- return whether the script has been executed directly
-- depth should be incremented for each function this is
-- called inside of.
-- stackoverflow.com/questions/49375638
M.isExe = function(depth)
  return _G.arg and not pcall(debug.getlocal, 5 + (depth or 0), 1)
end
assert(not M.isExe(), "Don't call shim directly")

M.parseList = function(args)
  local t = {}; for i, arg in ipairs(args) do
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
M.parseStr = function(s)
  if type(s) == 'table' then return s end
  if s:find'[%[%]\'"]' then error(
    [[parseStr does not support chars '"[]: ]]..s
  )end
  local args = {}; for a in s:gmatch'%S+' do push(args, a) end
  return M.parseList(args)
end

M.parse = function(v)
  if type(v) == 'string' then return M.parseStr(v)
  else                        return M.parseList(v) end
end

M.short = function(args, short, long, value)
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

-- Duck type: split a value or (flattened) list of values
-- nil results in an empty list
M.listSplit = function(val, sep)
  if val == nil then return {} end
  sep = '[^'..(sep or '%s')..']+'; local t = {}
  if type(val) == 'string' then
      for m in val:gmatch(sep) do push(t, m) end
  else
    for _, v in ipairs(val) do
      for m in v:gmatch(sep) do push(t, m) end
    end
  end
  return t
end

-- expand string keys into --key=value, ordered alphabetically.
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


-- Duck type: if value does not have a metatable then call ty(val)
-- Note: strings DO have a metatable.
--
-- This is primarily used for types which have a __call constructor,
-- such as metaty types.
M.new = function(ty, val)
  if val == nil then return end
  return getmetatable(val) and val or ty(val)
end

local function invalid(msg)
  io.stderr:write(msg); io.stderr:write'\n'
  io.stderr:write(DOC)
  os.exit(1)
end

local function checkHelp(sh, args)
  if args.help == true and sh.help then
    print(sh.help);
    if sh.subs then
      print('Subcommands:\n')
      local t = {}; for k in pairs(sh.subs) do table.insert(t, k) end
      table.sort(t)
      for _, s in ipairs(t) do print('  '..s) end
    end
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

return setmetatable(M, {
  __call=function(ty_, sh)
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
  end,
})

local add, sfmt = table.insert, string.format
local M = {}

local function addKV(t, k, v)
  local e = t[k]; if e then
    if type(e) == 'table' then add(e, v)
    else t[k] = {e, v} end
  else t[k] = v end
end

-- return whether the script has been executed directly
-- depth should be incremented for each function this is
-- called inside of.
-- stackoverflow.com/questions/49375638
function M.isExe(depth)
  return _G.arg and not pcall(debug.getlocal, 5 + (depth or 0), 1)
end
assert(not M.isExe(), "Don't call shim directly")

function M.parse(args)
  local t = {}
  for i, arg in ipairs(args) do
    if arg:find'^%-%w+' then
      for c in arg:sub(2):gmatch('.') do
        addKV(t, c, true)
      end
    elseif arg:find'^%-%-[^-]+' then
      local k, v = arg:match('(.-)=(.*)', 3)
      if k then addKV(t, k, v)
      else      addKV(t, arg:sub(3), true) end
    else        add(t, arg) end
  end
  return t
end

-- parses the string by splititng via whitespace.
-- Asserts the string contains no special chars: '"[]
-- This is for convinience, use a table if it's not enough.
function M.parseStr(s, duck)
  if duck and type(s) == 'table' then return s end
  if s:find'[%[%]\'"]' then error(
    'parseStr is split on whitespace: '..s
  )end
  return M.parse(s:find'%S+')
end

function M.short(args, short, long, value)
  if args[short] then args[long] = value; args[short] = nil end
end

local BOOLS = {
  [true]=true,   ['true']=true,   ['yes']=true, ['1']=true,
  [false]=false, ['false']=false, ['no']=false, ['0']=false,
}

-- Duck type: always return a boolean. See BOOLS (above) for mapping.
-- Note: nil -> nil
function M.boolean(v)
  if v == nil then return nil end
  local b = BOOLS[v] if b ~= nil then return b end
  error('invalid boolean: '..tostring(v))
end
function M.bools(args, ...)
  for _, arg in ipairs{...} do
    args[arg] = M.boolean(args[arg])
  end
end


-- Duck type: always return a number
function M.number(num)
  if num == nil then return nil end
  return (type(num)=='number') and num or tonumber(num)
end

-- Duck type: always return a list.
-- default controls val==nil
-- empty   controls val==''
function M.list(val, default, empty)
  if val == nil then return default or {} end
  if empty and val == '' then return empty end
  return (type(val) == 'table') and val or {val}
end

-- Duck type: split a value or (flattened) list of values
-- nil results in an empty list
function M.listSplit(val, sep)
  if val == nil then return {} end
  sep = '[^'..(sep or '%s')..']+'; local t = {}
  if type(val) == 'string' then
      for m in val:gmatch(sep) do add(t, m) end
  else
    for _, v in ipairs(val) do
      for m in v:gmatch(sep) do add(t, m) end
    end
  end
  return t
end

-- Duck type: if value does not have a metatable then call ty(val)
-- Note: strings DO have a metatable.
--
-- This is primarily used for types which have a __call constructor,
-- such as metaty types.
function M.new(ty, val)
  if val == nil then return end
  return getmetatable(val) and val or ty(val)
end

local function invalid(msg)
  io.stderr:write(msg); io.stderr:write'\n'
  io.stderr:write(DOC)
  os.exit(1)
end

local function checkHelp(sh, args)
  if sh.help and args.help == true then
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
  local args = M.parse(arg)
  ::restart::
  if sh.exe then
    checkHelp(sh, args)
    sh.exe(args, true)
  else
    if not args[1] then
      checkHelp(sh, args)
      invalid'Error: must specify a subcommand.'
    end
    sh = sh.subs[args[1]]
    if not sh then invalid(sfmt(
      'Error: unknown subcommand %q', args[1]
    ))end
    table.remove(args, 1)
    goto restart
  end
end

return setmetatable(M, {
  __call=function(ty_, sh)
    if sh.exe and sh.subs then error(
      'must specify exe OR subs, not both'
    )end
    if not (sh.exe or sh.subs) then error(
      'must specify one of: exe, subs'
    )end
    if _G.arg and M.isExe(1) then
      shimcall(sh)
      os.exit(0)
    end
    return setmetatable(sh, {
      __name='SHIM',
      __call=shimcall,
    })
  end,
})

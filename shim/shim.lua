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
    if arg:find'^%-%-[^-]+' then
      local k, v = arg:match('(.-)=(.+)', 3)
      if k then addKV(t, k, v)
      else      addKV(t, arg:sub(3), true) end
    else        add(t, arg) end
  end
  return t
end

local BOOLS = {
  [true]=true,   ['true']=true,   ['yes']=true, ['1']=true,
  [false]=false, ['false']=false, ['no']=false, ['0']=false,
}

-- Duck type: always return a boolean. See BOOLS (above) for mapping.
-- Note: nil -> false
function M.boolean(v)
  if v == nil then return false end
  local b = BOOLS[v] if b ~= nil then return b end
  error('invalid boolean: '..tostring(v))
end

-- Duck type: always return a number
function M.number(num)
  return (type(num)=='number') and num or tonumber(num)
end

-- Duck type: always return a list.
function M.list(val, sep) return (type(val) == 'table') and val or {val} end

-- Duck type: split a value or (flattened) list of values
function M.listSplit(val, sep)
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
function M.new(ty, val) return getmetatable(val) and val or ty(val) end

local function invalid(msg)
  io.stderr:write(msg); io.stderr:write'\n'
  io.stderr:write(DOC)
  os.exit(1)
end

local function checkHelp(sh, args, subs)
  if sh.help and args.help == true then
    print(sh.help);
    if subs then
      print('Subcommands:\n')
      local t = {}; for k in pairs(subs) do table.insert(t, k) end
      table.sort(t)
      for _, s in ipairs(t) do print('  '..s) end
    end
    os.exit(0)
  end
end

return setmetatable(M, {
  __call=function(ty_, sh)
    if not _G.arg or not M.isExe(1) then return end
    local args = M.parse(arg)
    local exe = sh.exe; if exe then
      assert(not sh.subs, 'choose exe or subs')
      checkHelp(sh, args)
    else
      assert(sh.subs, 'app did not specify exe or subs')
      if not args[1] then
        checkHelp(sh, args, sh.subs)
        invalid'Error: must specify a subcommand.'
      end
      exe = sh.subs[args[1]]
      if not exe then invalid(sfmt('Error: unknown subcommand %q', args[1])) end
      table.remove(args, 1)
    end
    exe(args, true)
    os.exit(0)
  end,
})

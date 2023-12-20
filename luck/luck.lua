local mty = require'metaty'
local ds  = require'ds'
local df  = require'ds.file'
local pegl = require'pegl'
local lua = require'pegl.lua'

local sfmt, push = string.format, table.insert
local M = {}

M.LUCK = {
  meta = function() end,
  sfmt=sfmt, push=push,

  string=string, table=table, utf8=utf8,
  type=type,   select=select,
  pairs=pairs, ipairs=ipairs, next=next,
  error=error, assert=assert,

  -- Note: cannot include math because of random
  abs=math.abs, ceil=math.ceil, floor=math.floor,
  max=math.max, min=math.min,
  maxinteger=math.maxinteger, tonumber=tonumber,
}
M.LUCK.__index = function(e, i) return M.LUCK[i] end

M.createEnv = function(env)
  env.__index = function(e, i) return env[i] end
  setmetatable(env, M.LUCK)
  return env
end

M.loadraw = function(dat, env)
  local i = 1
  local fn = function() -- alternates between next line and newline
    local o = '\n'; if i < 0 then i = 1 - i
    else  o = dat[i];             i =   - i end
    return o
  end
  local res = setmetatable({}, env and M.createEnv(env) or M.LUCK)
  local e, err = load(fn, path, 'bt', res); if err then error(err) end
  e()
  setmetatable(res, nil)
  return res
end

M.loadMeta = function(dat, path)
  local r = ds.copy(lua.root); r.dbg = true
  local p = pegl.Parser:new(dat, r)
  local name = p:parse(lua.name)
  if not name or p:tokenStr(name) ~= 'meta' then return end
  local meta = p:parse(lua.call); if not meta then return end
  local metaDat = {'return'}
  local ok, res = ds.eval(
    'return '..ds.lines.sub(dat, pegl.nodeSpan(meta)),
    {}, 'luck metadata of '..path)
  mty.assertf(ok, 'Failed to load luck metadata: %s\nError:%s', path, meta)
  return res
end

M.Luck = mty.record'Luck'
  :fieldMaybe('name', 'string')
  :field'deps'
  :field'dat'
  :field'path'

local function _error(l, msg) error(sfmt('ERROR %s\n%s', l.path, msg)) end
local function _assertf(chk, l, fmt, ...)
  if not chk then _error(l, sfmt(fmt, ...)) end
end

M.Luck.fromMeta = function(ty_, meta, dat, path)
  local l = meta; l.dat, l.path = dat, path
  _assertf(not (l.name and l[1]), l, "name provided as both position and key")
  l.name = l.name or l[1]; l[1] = nil
  _assertf(l.name, 'must have a name')
  l.deps = l.deps or {}
  for k, v in pairs(l.deps) do
    _assertf(type(k) == 'string', l, 'dep name %s is not a string', k)
    _assertf(type(v) == 'string', l, 'value of dep %q is not a string', k)
  end
  return mty.newChecked(ty_, l)
end

M.loadMetas = function(paths)
  local lucks = {}
  for _, path in ipairs(paths) do
    local dat = df.LinesFile{io.open(path), len=true}
    local l = M.loadMeta(dat, path) or {}
    l = M.Luck:fromMeta(l, dat, path)
    if lucks[l.name] then
      _error(l, sfmt('name %s also used at %s (or path is repeated)',
                l.name, lucks[l.name].path))
    end
    lucks[l.name] = l
  end
  return lucks
end

M.load = function(paths)
  local lucks = M.loadMetas(paths)
  local depsMap = {}; for n, l in pairs(lucks) do depsMap[n] = l.deps end
  local missing = ds.dag.missing(depsMap)
  if not ds.isEmpty(missing) then error(
    'Unknown dependencies: '..mty.fmt(missing)
  )end
  local sorted = ds.dag.sort(depsMap)
  local built = {}
  for _, name in ipairs(sorted) do
    local env, l = {}, lucks[name]
    if not l then error(sfmt(
      'Cyclic dependency detected involving %q. Sorted: %s',
      name, mty.fmt(sorted)
    ))end
    for localName, depName in ipairs(l.deps) do
      local dep = built[depName]
      if not dep then error(sfmt(
        'Cyclic dependency detected involving %q and %q. Sorted: %s',
        name, depName, mty.fmt(sorted)
      ))end
      env[localName] = ds.deepcopy(dep)
    end
    built[name] = assert(M.loadraw(l.dat, env))
  end
  return built, lucks, sorted
end

M.single = mty.doc[[
luck.single(path) -> data

Load a single path which has no dependencies.
]](function(path)
  local dat = df.LinesFile{io.open(path), len=true}
  local meta = M.loadMeta(dat, path)
  assert(not meta or not meta.deps, 'single must have no deps')
  return assert(M.loadraw(dat))
end)

return M

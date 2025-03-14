local G = G or _G

--- luck: lua configuration language
local M = G.mod and G.mod'luck' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds, lines  = require'ds', require'lines'
local LFile = require'lines.File'
local pegl = require'pegl'
local lua = require'pegl.lua'

local sfmt, push = string.format, table.insert

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

M.loadraw = function(dat, env, path)
  local res = setmetatable({}, env and M.createEnv(env) or M.LUCK)
  ds.check(2, load(ds.lineschunk(dat), path, 'bt', res))()
  setmetatable(res, nil)
  return res
end

M.loadMeta = function(dat, path)
  local r = ds.copy(lua.root)
  local p = pegl.Parser:new(dat, r)
  local name = p:parse(lua.name)
  if not name or p:tokenStr(name) ~= 'meta' then return end
  local meta = p:parse(lua.call); if not meta then return end
  local metaDat = {'return'}
  local ok, res = ds.eval(
    'return '..lines.sub(dat, pegl.nodeSpan(meta)),
    {}, 'luck metadata of '..path)
  fmt.assertf(ok, 'Failed to load luck metadata: %s\nError:%s', path, meta)
  return res
end

M.Luck = mty'Luck' {
  'name[string]',
  'deps', 'dat', 'path',
}

--- internal "luck" variants of error/assertf
local function lerror(l, msg) error(sfmt('ERROR %s\n%s', l.path, msg)) end
local function lassertf(chk, l, fmt, ...)
  if not chk then lerror(l, sfmt(fmt, ...)) end
end

M.Luck.fromMeta = function(T, meta, dat, path)
  local l = meta; l.dat, l.path = dat, path
  lassertf(not (l.name and l[1]), l, "name provided as both position and key")
  l.name = l.name or l[1]; l[1] = nil
  lassertf(l.name, 'must have a name')
  l.deps = l.deps or {}
  for k, v in pairs(l.deps) do
    lassertf(type(k) == 'string', l, 'dep name %s is not a string', k)
    lassertf(type(v) == 'string', l, 'value of dep %q is not a string', k)
  end
  return mty.construct(T, l)
end

M.loadMetas = function(paths)
  local lucks = {}
  for _, path in ipairs(paths) do
    local dat = assert(LFile{path=path})
    local l = M.loadMeta(dat, path) or {}
    l = M.Luck:fromMeta(l, dat, path)
    if lucks[l.name] then
      lerror(l, sfmt('name %s also used at %s (or path is repeated)',
                l.name, lucks[l.name].path))
    end
    lucks[l.name] = l
  end
  return lucks
end

M.loadall = function(paths, allenv) --> built, lucks, sorted
  allenv = allenv or {}
  local lucks = M.loadMetas(paths)
  local depsMap = {}
  for n, l in pairs(lucks) do depsMap[n] = ds.values(l.deps) end
  local missing = ds.dag.missing(depsMap)
  if not ds.isEmpty(missing) then error(
    'Unknown dependencies: '..fmt(missing)
  )end
  local sorted = ds.dag.sort(depsMap)
  local built = {}
  for _, name in ipairs(sorted) do
    local env, l = ds.copy(allenv), lucks[name]
    if not l then error(fmt.format(
      'Cyclic dependency detected involving %q. Sorted: %q',
      name, sorted
    ))end
    for localName, depName in pairs(l.deps) do
      local dep = built[depName]
      if not dep then error(fmt.format(
        'Cyclic dependency detected involving %q and %q. Sorted: %q',
        name, depName, sorted
      ))end
      env[localName] = ds.deepcopy(dep)
    end
    built[name] = assert(M.loadraw(l.dat, env))
  end
  return built, lucks, sorted
end

--- Load a single path which has no dependencies.
M.load = function(path, env) --> table
  local dat = assert(LFile{path=path})
  local meta = M.loadMeta(dat, path)
  assert(not meta or not meta.deps, 'single must have no deps')
  return assert(M.loadraw(dat, env))
end

return M

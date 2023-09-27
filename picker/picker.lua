-- NOTE: this code is bollocks. I copy/pasted it from civlib/lua/civ.lua
-- Pretty much everything about it is WRONG and needs to be re-written.
--
-- The MAJOR architecture change is that building the query MUST be separate
-- from acting on the query. The query builder MUST be separate from the data.
-- Right now they are held together in some kind of frankenquery which fails
-- as soon as it's used on all but the simplest cases.

-- ###################
-- # Picker / Query
-- Picker is an ergonomic way to query over a list of structs
-- while using struct indexes
--
-- Example use:
--   l = List{
--     A{a1='one',   a2=1},
--     A{a1='two',   a2=2},
--     A{a1='three', a2=3},
--   }
--   p = Picker(A, l) -- construct the picker with the type.
--
--   -- `.q` creates a Query object. Here we filter/query by equality:
--   oneOnly  = p.q.a1:eq('one') 
--   twoThree = p.q.a2:in_{2, 3}.a1:eq('two')

local DisplayCell = struct('DisplayCell',
  {{'lines', List}, {'width', Int}})
local DisplayCol = struct('DisplayCol',
  {{'data', List}, {'width', Int}})

local Display = newTy('Display')
constructor(Display, function(ty_, struct, iter)
  local totalW, cols = 0, Map{}
  for _, name in ipairs(struct['#ordered']) do
    cols[name] = DisplayCol{data=List{}, width=0}
  end
  local len, dWidth = 0, 0
  for _, row in iter do
    len = len + 1
    for _, cname in ipairs(struct['#ordered']) do
      local v = row[cname]
      local w, txt = 0, tostring(Fmt.pretty(v))
      local cLines = List{}
      local first = true
      for line in lines(txt) do
        if first and trim(line) == '' then -- remove empty lines at front
        else
          first, w = false, max(w, string.len(line))
          cLines:add(line)
        end
      end
      -- remove lines at the end
      while '' == trim(cLines[#cLines]) do cLines[#cLines] = null end
      local dcol = cols[cname]
      dWidth = max(dWidth, w)
      dcol.width = max(dcol.width, w)
      dcol.data:add(DisplayCell{lines=cLines, width=w})
    end
  end
  return setmetatable({
    struct=struct, cols=cols, len=len, width=dWidth,
  }, ty_)
end)
local COL_SEP = ' | '
method(Display, '__tostring', function(self)
  for ri=1, self.len do
    for c, dCol in pairs(self.cols) do
    end
  end
  local availW = 100
  local b = setmetatable({indent='  '}, Fmt)
  local widths, heights = Map{}, List{}
  local colNames = self.struct['#ordered']

  for _, c in ipairs(colNames) do heights[0] = 1 end
  for ri=1, self.len do
    local r = 0
    for _, c in ipairs(colNames) do
      r = max(r, #self.cols[c].data[ri].lines)
    end
    heights[ri] = r
  end

  if self.width <= availW - (#COL_SEP * #colNames) then
    for _, c in ipairs(colNames) do
      widths[c] = max(#c, self.cols[c].width)
    end
  else error('auto-width not impl') end

  local addCell = function(ci, ri, li, c, lines, sep, filler)
    if li > #lines then if filler or ci < #colNames then
        fillBuf(b, widths[c], filler)
      end
    else
      local l = lines[li]
      table.insert(b, l)
      if filler or ci < #colNames then
        fillBuf(b, widths[c] - string.len(l), filler)
      end
    end
    if(ci < #colNames)  then table.insert(b, sep or COL_SEP)
    else table.insert(b, '\n') end
  end

  -------+-----------+------ = header separator
  local breaker = function(filler, sep)
    for ci, c in ipairs(colNames) do
      local b = List{}; fillBuf(b, widths[c], filler)
      addCell(ci, 0, 1, c, {}, sep, filler)
    end
  end

  breaker(BufFillerHeader, '=+=')
  -- bob | george    | ringo = header
  for ci, c in ipairs(colNames) do addCell(ci, 0, 1, c, {c}) end
  breaker(BufFillerHeader, '=+=')

  for ri = 1, self.len do
    for li = 1, heights[ri] do
      for ci, c in ipairs(colNames) do
        local lines = self.cols[c].data[ri].lines
          addCell(ci, ri, li, c, lines)
      end
    end
    breaker(BufFillerRow, ' + ')
  end
  return concat(b)
end)


local Picker = newTy('Picker')
local Query = struct('Query', {
    -- data comes from one of
    -- (picker,i[ndexIter]) or (iter, struct)
    {'#picker', Picker, false}, {'#i', nil, false},
    {'#iter', nil, false}, {'#struct', nil, false},
    {'#iNew', nil, false},

    -- path and ops are built-up by user
    {'#path', List}, {'#ops', List},
  })
method(Query, 'debug', function(self)
  return string.format(
      'Query[%s %s %s]', rawget(self, '#ops'),
      rawget(self, '#iNew'), rawget(self, '#iter'))
end)
local PathBuilder = struct('PathBuilder', {'#query'})
local QueryOp = struct('Op',
  {{'name', Str}, {'path'}, {'value'}})

local function fmtStructFull(stTy)
  local endAdd, b = 1, List{stTy.__name, '{'}
  for _, field in ipairs(stTy['#ordered']) do
    local fieldTy = stTy['#tys'][field]
    if true == fieldTy then fieldTy = 'Any' end
    b:extend{field, ':', tostring(fieldTy), ' '}
    endAdd = 0
  end
  b[#b + endAdd] = '}'
  return concat(b)
end
local function genStruct(name, namedTys)
  local repo = genTyRepo(namedTys, {name})
  if not repo then error(string.format(
    "All types must be defined in path: %s", sel))
  end
  if repo.ty then return repo.ty end
  local fields = List{}
  local i = 1; while i+1 <= #namedTys do
    fields:add{namedTys[i], namedTys[i+1]}
    i = i + 2
  end
  local st = struct(name, fields); repo.ty = st
  getmetatable(st).__tostring = fmtStructFull
  return repo.ty
end

-- A set of query operations to perform on a Picker
-- path is built up by multiple field accesses.
method(Query, '__tostring', function(self) return 'Query' end)
method(Query, 'new',  function(picker)
  return Query{['#picker']=picker, ['#path']=List{}, ['#ops']=List{},
               ['#i']=Range(1, picker.len)}
end)
method(Query, 'iter', function(self)
  assert(Query == ty(self))
  local r = rawget(self, '#iNew')
  if r then self['#i'] = r()
  else r = rawget(self, '#picker');
    if r then self['#i'] = Range(1, r.len) end
  end
  return self
end)

-- A picker itself, which holds the struct type
-- and the data (or the way to access the data)
constructor(Picker, function(ty, struct, data)
  local p = {struct=struct, data=data, len=#data,
             indexes=Map{}}
  return setmetatable(p, ty)
end)
method(Picker, '__index', function(self, k)
  if 'q' == k then return Query.new(self) end
  local mv = getmetatable(self)[k]; if mv then return mv end
  error(k .. ' not on Picker. Use Picker.q to start query')
end)
method(Picker, '__tostring', function(self)
  return string.format("Picker[%s len=%s]",
    rawget(self, 'struct').__name, rawget(self, 'len'))
end)

local function queryStruct(q)
  return rawget(q, '#struct') or q['#picker'].struct
end
local function queryCheckTy(query, ty_, path)
  path = path or query['#path']
  return tyCheckPath(queryStruct(query), path, ty_)
end

local function _queryOpImpl(query, op, value, ty_)
  queryCheckTy(query, ty_)
  query['#ops']:add(QueryOp{
    name=op, path=query['#path'], value=value})
  query['#path'] = List{}
  return query

end
local function _queryOp(op)
  return function(self, value)
    assert(Query == ty(self))
    queryCheckTy(self, ty(value))
    self['#ops']:add(QueryOp{
      name=op, path=self['#path'], value=value})
    self['#path'] = List{}
    return self
  end
end
for _, op in pairs({'filter', 'lt', 'lte', 'gt', 'gte'}) do
  method(Query, op, _queryOp(op))
end

local function queryCreateIndexes(query, filter)
  return idx
end

local function queryIndexPath(query, op, vTy, path)
  path = path or query['#path']
  local pty = queryCheckTy(query, vTy, path)
  local indexes = (query['#picker']or{}).indexes
  if not indexes or not KEY_TYS[pty] then return nil end
  return List{op, concat(path)}, query['#picker'], indexes
end
-- Get or create query indexes using filter.
local function queryIndexes(query, op, v, vTy, filter, path)
  local path, picker, indexes = queryIndexPath(query, op, vTy, path)
  if 'table' == type(v) then path:extend(v:asSorted())
  else                       path:add(v) end
  indexes = indexes:getPath(path, function(d, i)
    if i < #path then return Map{}
    else              return List{} end
  end)
  if #indexes ~= 0 then return indexes end
  -- fill indexes
  local stTy, path = queryStruct(query), query['#path']
  for i, v in ipairs(picker.data) do
    if filter(pathVal(v, path)) then indexes:add(i) end
  end
  return indexes
end

local function queryUseIndexes(query, idx)
  if not idx then return nil end
  local iNew = function() return idx:iterFn() end
  query['#iNew'], query['#i'] = iNew, idx:iterFn()
  query['#path'] = List{}
  return query
end

local normalEq = _queryOp('eq')

method(Query, 'eq', function(self, value)
  assert(Query == ty(self))
  local idx = queryIndexes(self, 'eq', value, ty(value), isEq(value))
  if idx then return queryUseIndexes(self, idx) end
  return normalEq(self, value)
end)
method(Query, 'in_', function(self, value)
  assert(Query == ty(self))
  if 'table' == type(value) then value = Set(value) end
  if Set ~= ty(value) then error(
    "in_ must be on Set, got " .. tyName(value)
  )end
  local idx = Set{}; local cTy = containerTy(value)
  for v in value:iter() do
    local add = queryIndexes(self, 'in_', v, cTy, isEq(v))
    if not add then idx = nil; break end
    idx:update(add)
  end
  if idx then return queryUseIndexes(self, idx) end
end)

local function querySelect(iter, stTy, paths)
  return function()
    local i, st = iter(); if nil == i then return end
    local keys = {}; for key, path in pairs(paths) do
      keys[key] = pathVal(st, path)
    end
    return i, stTy(keys)
  end
end
-- select{'a.b', 'c.d'}}       -- accessible through .c, .d
-- select{{x='a.b', y='c.d'}}, -- now .x, .y
method(Query, 'select', function(self, sel)
  assert(Query == ty(self))
  local st = queryStruct(self)
  local paths, tys, namedTys = {}, {}, List{}
  for key, p in pairs(sel) do
    p = makePath(p)
    -- by index uses the last field name
    if 'number' == type(key) then key = p[#p] end
    if 'string' ~= type(key) then error(
      'must provide name for non-key path: ' .. tfmt(key)
    )end
    if paths[key] then error(
      'key used multiple times: ' .. key
    )end
    paths[key] = p; tys[key] = pathTy(st, p)
    namedTys:extend{key, tys[key]}
  end
  self['#path'] = List{}
  local st = genStruct('Q', namedTys)
  return Query{
    ['#iter']=querySelect(self:iter(), st, paths),
    ['#struct']=st,
    ['#path']=List{}, ['#ops']=List{},
  }
end)

-- The __index function for Query.
-- Mostly you do queries doing `q.structField.rightField.lt(3)`
--
-- If a struct field is (i.e) 'lt' you can use `path` like so:
--   q.path.lt.eq(3) -- lt less equal to 3
local function buildQuery(query, field)
  local st = queryStruct(query)
  st = pathTy(st, rawget(query, '#path'))
  local tys = assert(rawget(st, '#tys'), civ.tfmt(st))
  if not tys[field] then error(
    string.format("%s does not have field %s", st, field)
  )end
  query['#path']:add(field);
  return query
end
method(Query, '__index', function(self, k)
  local mv = getmetatable(self)[k]; if mv then return mv end
  if 'path' == k then return PathBuilder{['#query']=self} end
  return buildQuery(self, k)
end)
method(PathBuilder, '__index', function(self, field)
  return buildQuery(self['#query'])
end)

local opIml = {
  in_=function(op, v)    return op.value[v]     end,
  filter=function(op, f) return f(op.value)     end,
  eq =function(op, v) return op.value == v      end,
  lt =function(op, v) return op.value <  v      end,
  lte=function(op, v) return op.value <= v      end,
  gt =function(op, v) return op.value >  v      end,
  gte=function(op, v) return op.value >= v      end,
}
-- apply the query operations to the value
local function queryKeep(self, v)
  for _, op in ipairs(self['#ops']) do
    if not opIml[op.name](op, pathVal(v, op.path)) then
      return false
    end
  end
  return true
end
method(Query, '__call', function(self)
  local iter = rawget(self, '#iter')
  if iter then return iter() end
  while true do
    iter = self['#i']; local i = iter()
    local data = self['#picker'].data
    if not i or i > #data then return      end
    local v = data[i]
    if queryKeep(self, v) then return i, v end
  end
end)
method(Query, 'toList', function(self)
  assert(Query == ty(self))
  return List.fromIter(callMethod(self, 'iter'))
end)

local function asQuery(t)
  if(ty(t) == Query)  then return t end
  if(ty(t) == Picker) then return Query.new(t) end
  error("Invalid query type: " .. tostring(ty(t)))
end

method(Query, 'joinEq', function(
    left, leftField, right, rightField, idxQuery)
  assert(Query == ty(left))
  leftField = makePath(leftField); rightField = makePath(rightField)
  local idxField, noIdxField, noIdxQuery
  if idxQuery == right then
    right = asQuery(right); idxQuery = right
    idxField = rightField; noIdxField = leftField
    right = idxQuery
  else
    right = asQuery(right); noIdxQuery = right
    idxField = leftField;   noIdxField = rightField
    idxQuery = left
  end
  local st = queryStruct(idxQuery)
  local pty = pathTy(st, idxField)
  local path, idxPicker, baseIdx = queryIndexPath(
    idxQuery, 'eq', pty, idxField)

  if not idxPicker then
    idxPicker = Picker(
      assert(idxQuery['#struct']), List.fromIter(idxQuery))
  end
  local idxData = idxPicker.data
  local indexes = baseIdx:getPath(path, Map.empty)
  if indexes:isEmpty() then
    for i, st in ipairs(idxData) do
      local v = pathVal(st, idxField)
      indexes:get(v, List.empty):add(i)
    end
  end

  local joined = List{}
  local genSt = genStruct(
    'joinEq',
    {'j1', queryStruct(left), 'j2', queryStruct(right)})

  for i, st in noIdxQuery do
    local v = pathVal(st, noIdxField)
    for _, di in ipairs(indexes[v] or {}) do
      if left == idxQuery then joined:add(genSt{
        j1=idxData[di], j2=st})
      else                     joined:add(genSt{
        j1=st,          j2=idxData[di]})
      end
    end
  end
  return Picker(genSt, joined)
end)

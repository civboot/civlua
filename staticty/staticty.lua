
----------------------------------------------
-- Fn: register function types

M.assertIsTys = function(tys)
  for i, ty_ in ipairs(tys) do
    local err = M.isTyErrMsg(ty_)
    M.assertf(not err, '[arg %s] %s', i, err)
  end
  return tys
end

M.FnInfo = M.record('FnInfo')
  :field('debug', M.Any)
  :field('name', 'string', '')

M.Fn = M.record('Fn', {
  __call=function(ty_, inputs)
    assert(M.ty(inputs) == 'table', 'inputs must be a raw table')
    local t = {
      inputs=M.assertIsTys(inputs),
      outputs={},
    }
    return M.newChecked(ty_, t)
  end
})
  :field('inputs',  'table') :field('outputs', 'table')
  :fieldMaybe('iMaybes', 'table')
  :fieldMaybe('oMaybes', 'table')

M.forceCheckRecord(M.Fn)

M.Fn.inpMaybe = function(self, m)
  M.assertf(M.ty(m) == 'table', 'inpMaybe must be list of booleans')
  M.assertf(#m == #self.inputs, 'inpMaybe len must be same as inp')
  self.iMaybes = m
  return self
end

M.Fn.out = function(self, outputs)
  assert(M.ty(outputs) == 'table', 'outputs must be a raw table')
  self.outputs = M.assertIsTys(outputs)
  return self
end
M.Fn.outMaybe = function(self, m)
  M.assertf(M.ty(m) == 'table', 'outMaybe must be list of booleans')
  M.assertf(#m == #self.outputs, 'outMaybe len must be same as out')
  self.oMaybes = m
  return self
end

M.Fn.apply = function(self, fn, name)
  if M.FNS[fn] then errorf('fn already applied: %s', fmt(fn)) end
  local dbg = debug.getinfo(fn, 'nS')
  M.FNS_INFO[fn] = M.FnInfo{debug=dbg, name=name or dbg.name}
  M.FNS[fn] = self
  local unchecked = fn
  if CHECK then
    local chk = Checker{}
    local inner = fn
    fn = function(...)
      M.tysCheck(chk, nil, {...}, self.inputs, self.iMaybes, ' (fn inp)')
      local o = {inner(...)}
      M.tysCheck(chk, nil, o, self.outputs, self.oMaybes, ' (fn out)')
      return table.unpack(o)
    end
    M.FNS_INFO[fn] = FnInfo{debug=dbg, name=name or dbg.name}
    M.FNS[fn] = self
    M.FNS_UNCHECKED[fn] = unchecked
  end
  return fn
end

----------------------------------------------
-- Generic Types
--
-- The user should use generics like:
--   local GenFn = Fn{g'A', g'A'}:out{g'A'}
--   local GenType = record'GenType'
--     :generic'A' :generic('B', Table{I='A'})
--     :field(a, g'A')
--
--   GenType.myMethod = Method{g'A'}:out{g'B'}
--   :apply(function(self, a) ... end)
--
--   local TypeNum = GenType{A='number'}
--   local n = TypeNum{a=7}
--   ... call functions on n and access n.a normally

local GENERIC_VARS = {} -- Cached genvar singletons
local GENERICS = {}     -- Trie of generic type singletons

-- Note: Do NOT create these directly, use the `g()` function.
M.g = setmetatable({
  __name='GenVar', 
  __index=function(v, k)
      if k == 'var' then return v['#var__doNotSet'] end
      error('GenVar does not have field: '..k)
    end,
}, {
  __name='Ty<GenVar>',
  __call=function(ty_, var)
    assert(ty_ == M.g)
    local v = GENERIC_VARS[var]
    if not v then
      v = {__name='<'..var..'>', ['#var__doNotSet']=var}
      GENERIC_VARS[var] = setmetatable(v, M.g)
    end
    return v
  end,
})

-- Do record type checking and return new constraints
-- For example: recordCheck(nil, Table{I=g'I'}, Table{I='number'})
M.recordCheck = function(chk, anchor, reqTy, giveTy)
  pnt('!! recordCheck', tostring(anchor), reqTy, giveTy)
  -- handled in Checker.check
  assert(type(reqTy) == 'table'); assert(type(giveTy) == 'table')
  assert(reqTy ~= giveTy)

  if reqTy.__kind == 'generic' then
    anchor = M.chooseAnchor(c, reqTy)
    assertf(anchor, 'No anchor type: require=%s given=%s', reqTy, giveTy)
    for vname in pairs(reqTy.__genvars) do
      local rTy = chk:resolveGenVar(anchor, vname)
      local gTy = giveTy.__genvars[vname]
      pnt(sfmt('!! genvar=%s: ', vname), M.tyCheckMsg(rTy, gTy))
      if not chk:check(anchor, rTy, gTy) then return nil end
    end
    return reqTy
  end
  -- TODO: parents check
  return nil
end

----------------------
-- Create New Generic Type

-- Create a new type with the variables substituted from varMap
M.substituteVars = function(genTy, varMap, new)
  assert(genTy.__kind == 'generic', 'Cannot substitute non-generic')
  local t = copy(genTy)
  local mt = copy(getmetatable(genTy))
  setmetatable(t, mt)
  t.__name = t.__name..M.fmt(varMap)
  t.__kind = 'concrete'
  mt.__name = 'Ty<'..t.__name..'>'
  mt.__call = assert(t.__gencall)
  t.__gencall = nil
  t.__fromgen = genTy
  -- TODO: check constraints
  for k in pairs(t.__genvars) do t.__genvars[k] = varMap[k] or M.Any end
  return t
end

-- new (aka __call) for Generic types
-- i.e. Table{I='number'} calls newGeneric
-- Attempts to lookup the (existing) generic type,
-- else creates a new one
M.newGeneric = function(genTy, varMap, newGenerated)
  -- GENERICS is a trie that for record'MyGen':generic'A':generic'B'
  -- might look like:
  -- {MyGen={
  --   --<A>   <B>      or alternate        <B>
  --   number={number=MyGen{number,number}, string=MyGen{number,string}},
  --   --<A>    <B>
  --   string={ ... },
  --   Any={...},
  -- }}
  local c = getOrEmpty(GENERICS, genTy)
  local vars = genTy.__genvars
  local gen
  for i, vname in ipairs(vars) do
    vTy = varMap[vname] or M.Any
    if i < #vars then c = getOrEmpty(c, vTy)
    else -- last item: either get or create substituted type
      gen = c[vTy]; if not gen then
        gen = substituteVars(genTy, varMap, newGenerated)
        c[vTy] = gen
      end
    end
  end
  return assert(gen)
end

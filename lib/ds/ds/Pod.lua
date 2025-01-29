local mty = require'metaty'

--- Pod: object which converts values to/from plain old data.
local Pod = mty'Pod'{
  'fieldIds [boolean]: if true use the fieldIds when possible',
}

local ds = require'ds'
local push = table.insert

local CONCRETE = {
  boolean=ds.iden, number=ds.iden, string=ds.iden,
}

local NATIVE = ds.copy(CONCRETE, {
  ['nil']=ds.iden,
  table = function(t)
    if type(t) ~= 'table' then error('invalid table type: '..type(t)) end
    assert(ds.isPod(t), 'table is not plain-old-data')
    return t
  end
})

--- Handles concrete non-nil types (boolean, number, string)
Pod.Concrete = mty'Pod.Concrete' {}
Pod.Concrete.__toPod = function(self, pod, v)
  return (CONCRETE[type(v)] or error('nonconrete type: '..type(v))) (v)
end
Pod.Conrete.__fromPod = Pod.Concrete.__toPod

--- Handles all native types (nil, boolean, number, string, table)
Pod.Native = mty'Pod.Native' {}
Pod.Native.__toPod = function(self, pod, v)
  return (NATIVE[type(v)] or error('nonnative type: '..type(v))) (v)
end
Pod.Native.__fromPod = Pod.Native.__toPod

--- Poder for a list of items with a type.
Pod.List = mty'Pod.List' {'Item [Type]: the type of each list item'}
Pod.List.__toPod = function(self, pod, l)
  local I, p = self.Item, {}
  for i, v in ipairs(l) do p[i] = I:__toPod(pod, v) end
  return p
end
Pod.List.__fromPod = function(self, pod, p)
  local I, l = self.Item, {}
  for i, v in ipairs(l) do l[i] = I:__fromPod(pod, v) end
  return l
end

--- Poder for a map of key/value pairs.
--- The default key type is Concrete.
Pod.Map = mty'Pod.Map' {
  'Key [Type]: keys type', Key=Pod.Concrete,
  'Value [Type]: values type',
}
Pod.Map.__toPod = function(self, pod, m)
  local K, V, p = self.Key, self.Value, {}
  for k, v in pairs(m) do
    p[K:__toPod(pod, k)] = V:__toPod(pod, v)
  end
  return p
end
Pod.Map.__fromPod = function(self, pod, p)
  local K, V, m = self.Key, self.Value, {}
  for k, v in pairs(p) do
    m[K:__fromPod(pod, k)] = V:__fromPod(pod, v)
  end
  return m
end

local Native = Pod.Native
Pod.to = function(pod, v, poder)
  poder = poder or Native
  return poder:__toPod(pod, v)
end
Pod.from = function(pod, v, poder)
  poder = poder or Native
  return poder:__fromPod(pod, v)
end

Pod.mty_toPod = function(T, pod, t)
end

--- Make metaty type convertable to/from plain-old-data
Pod.makePod = function(T, types)
  local errs = {}
  for f, tyname in pairs(mt.__fields) do
    if type(f) ~= 'string' then goto c1 end
    if tyname == true then
      push(errs, f..' does not have tyname specified')
    end
    local podder
    if tyname:match'%b[]' then
      podder = getPodder(tyname:sub(2,-2))
    elseif tyname:match'%b{}' then
      tyname = tyname:sub(2,-2); local kname, vname = tyname:match'^%s*(.-)%s*:%s*(.-)%s*$'
      if kname then
        podder = Pod.Map { K=getPodder(kname), V=getPodder(vname) }
      else
        podder = Pod.List { I=getPodder(tyname) }
      end
    else error('unrecognized tyname: '..tyname) end
    mt.__fields[f] = podder
    ::c1::
  end

end

return Pod

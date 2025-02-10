local mty = require'metaty'

--- Linked List File: file which supports pushing and popping nodes
--- to a file-backed linked-list.
---
--- Nodes are stored as a single-linked-list but returned with
--- knowledge of the previous index (for popping).
local LLFile = mty'fd.LLFile' {
  'szi [int]: size of ll indexes. Limits total number of\n'
  ..'possible nodes',
  'szv [int]: size of ll node values.',
  'fi [df.IFile]: holds actual data',
  '_encode [fn(i, v) -> str]', '_decode [fn(str) -> (i, v)]'
}

local ds = require'ds'
local IFile = require'fd.IFile'

local mtype = math.type
local pack, unpack = string.pack, string.unpack
local sfmt, ssub, srep = string.format, string.sub, string.rep
local construct = mty.construct
local popk = ds.popk

--- Iterable Node (call to get next node).
---
--- Node also has methods for modifying the LL.
LLFile.Node = mty'fd.LLFile.Node' {
  'll [fd.LLFile]: LLFile this node refers to',
  'i [int]: index of this node',
  'pi [int]: index of previous node',
  'ni [int]: index of next node',
  'val [str]: value of this node',
}
local Node = LLFile.Node

getmetatable(LL).__call = function() error'use load() or create()' end

local llNew = function(T, t, fi)
  t.fi = fi
  local vsi, ifmt, vfmt = t.szi + 1, 'I'..t.szi, 'I'..t.szv
  t._encode = function(i, v) return pack(ifmt, i)..v end
  t._decode = function(s)    return unpack(ifmt, s), ssub(s, vsi) end
  return construct(T, t)
end

--- create new LL File
LLFile.create = function(T, t)
  local fi, err = IFile:create(t.szi + t.szv, popk(t, 'path'))
  if not fi then return nil, err end
  return llNew(T, t, fi)
end

--- load existing LL File
LLFile.load = function(T, t)
  local path, mode = popk(t, 'path'), popk(t, 'mode')
  local fi, err = IFile:load(t.szi + t.szv, path, mode)
  if not fi then return nil, err end
  return llNew(T, t, fi)
end

LLFile.__index = function(ll, i)
  assert(mtype(i) == 'integer', 'index must be integer')
  local nstr = ll.fi[i]; if not nstr then return end
  local ni, val = ll._decode(node); if ni == 0 then ni = nil end
  return Node{ll=ll, i=i, --[[pi=nil]], ni=ni, val=val}
end

LLFile.__call = function(ll, i, v, ni)
  assert(mtype(i) == 'integer', 'index must be integer')
  ll.fi[i] = ll._encode(ni or 0, v)
end

--- iterate through nodes by calling them
Node.__call = function(n)
  local ni = n.ni; if not ni then return end
  return n.ll[ni]
end

--- Remove node from LL
--- ["Note: the node will still be in the file, so this will forever
---   consume diskspace unless cleaned in some way by another process.
--- ]
Node.remove = function(n)
  local ll, i, pi = n.ll, n.i, n.pi
  if pi then -- update prev to point to next
    local selfi, v = ll[pi]; assert(i == selfi)
    ll(pi, v, n.ni)
  end
end

--- push value to be after node.
Node.push = function(n, v)
  local ll = n.ll; local i = #ll.fi + 1
  ll(i,   v,   n.ni)
  ll(n.i, n.v, i)
end

return LLFile

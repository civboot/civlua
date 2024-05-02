local M = mod'doc_test'

-- some dosc
M.exampleFn = function() end
M.Example  = require'metaty'.record2'Example'{'a [int]', a=4}
M.Example.method = function() end

METATY_CHECK = true

local mty = require'metaty'
local doc = require'doc'
local T = require'civtest'
T.assertEq(mod.__newindex, getmetatable(M.Example).__newindex)
T.assertEq('doc_test.Example', DOC_NAME[M.Example])
T.assertEq('lib/doc/test.lua:5', DOC_LOC[M.Example])


local eFn =
'doc_test.exampleFn [function] (lib/doc/test.lua:4)'
local eRecord =
'doc_test.Example [Ty<Example>] (lib/doc/test.lua:5)\
## Fields\
  a               : [int] = 4         \
\
## Methods, Etc\
  __fields        : table             \
  __index         : Ty<Example>       (doc/test.lua:5)\
  __name          : string            \
  __newindex      : function          (metaty/metaty.lua:150)\
  method          : function          (doc/test.lua:6)\
'
local eDoc =
'doc_test [Mod] (lib/doc/test.lua:1)\
## Methods, Etc\
  Example         : Ty<Example>       (doc/test.lua:5)\
  __name          : string            \
  exampleFn       : function          (doc/test.lua:4)\
'
T.test('doc.get', function()
  T.assertEq(eFn,     mty.tostring(doc(M.exampleFn)))
  T.assertEq(eRecord, mty.tostring(doc(M.Example)))
  T.assertEq(eDoc,    mty.tostring(doc(M)))
end)

-- This was used to craft the for documentation
T.test('pairs', function()
  local function rawipairs(t, i)
    i = i + 1
    if i > #t then return nil end
    return i, t[i]
  end

  local function ipairs_(t)
    return rawipairs, t, 0
  end

  local e = {1, 2, 10, a=8, hello='hi'}
  local r = {}; for i, v in ipairs_(e) do r[i] = v end
  assert(#r == 3)
  assert(r[1] == 1); assert(r[2] == 2); assert(r[3] == 10);

  local function pairs_(t) return next, t, nil end
  r = {}; for k, v in pairs_(e) do r[k] = v end
  assert(#r == 3)
  assert(r[1] == 1); assert(r[2] == 2); assert(r[3] == 10);
  assert(r.a == 8);  assert(r.hello == 'hi')
end)

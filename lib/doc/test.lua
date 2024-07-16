local M = mod'doc_test'

-- document a fn
-- another line
M.exampleFn = function() end

-- document a metaty
-- another line
M.Example  = require'metaty''Example'{
  'a [int]', a=4,
}
M.Example.method = function() end

METATY_CHECK = true

local mty = require'metaty'
local doc = require'doc'
local T = require'civtest'
T.assertEq(mod.__newindex, getmetatable(M.Example).__newindex)
T.assertEq('doc_test.Example',    PKG_NAMES[M.Example])
T.assertEq('lib/doc/test.lua:11', PKG_LOC[M.Example])

T.test('findcode', function()
  local com, code = doc.findcode(M.exampleFn)
  T.assertEq({"-- document a fn", "-- another line"}, com)
  T.assertEq({"M.exampleFn = function() end"}, code)

  com, code = doc.findcode(M.Example)
  T.assertEq('-- document a metaty', com[1])
  T.assertEq('-- another line',      com[2])
  T.assertEq([[M.Example  = require'metaty''Example'{]], code[1])
  T.assertEq([[  'a [int]', a=4,]], code[2])
  T.assertEq('}', code[3])
end)

local eFn =
'## doc_test.exampleFn (lib/doc/test.lua:5) ty=function\
document a fn\
another line\
---- CODE ----\
M.exampleFn = function() end\
'

local mDoc =
"## doc_test (lib/doc/test.lua:1) ty=Ty<doc_test>\
\
## Methods, Etc\
  Example         : Ty<Example>       (doc/test.lua:11)\
  __name          : string            \
  exampleFn       : function          (doc/test.lua:5)\
---- CODE ----\
local M = mod'doc_test'\
"
T.test('doc.get', function()
  T.assertEq(eFn,     doc(M.exampleFn))
  T.assertEq(mDoc,    doc(M))
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

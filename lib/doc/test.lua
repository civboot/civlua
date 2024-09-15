local M = mod'doc_test'

--- document a fn
--- another line
M.exampleFn = function() end

--- document a metaty
--- another line
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
  T.assertEq({"--- document a fn", "--- another line"}, com)
  T.assertEq({"M.exampleFn = function() end"}, code)

  com, code = doc.findcode(M.Example)
  T.assertEq('--- document a metaty', com[1])
  T.assertEq('--- another line',      com[2])
  T.assertEq([[M.Example  = require'metaty''Example'{]], code[1])
  T.assertEq([[  'a [int]', a=4,]], code[2])
  T.assertEq('}', code[3])
end)

local eFn =
"[{h2}Function [:doc_test.exampleFn] [/lib/doc/test.lua:5] [@function] ]\
[$M.exampleFn = function() end]\
document a fn\
another line"


local mDoc =
"[{h2}Module [:doc_test] [/lib/doc/test.lua:1] [@Mod<doc_test>] ]\
\
[{table}\
+ [*Methods, Etc]\
+ [$Example]       | \\[[@Ty<Example>]\\] [/lib/doc/test.lua:11]\
+ [$__name]        | \\[[@string]\\] \
+ [$exampleFn]     | \\[[@function]\\] [/lib/doc/test.lua:5]\
]"

T.test('doc.get', function()
  T.assertEq(eFn,     doc.docstr(M.exampleFn))
  T.assertEq(eFn,     doc.docstr'doc_test.exampleFn')
  T.assertEq(mDoc,    doc.docstr(M))
  T.assertEq(mDoc,    doc.docstr'doc_test')
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

T.test('record', function()

  local expect =
"[{h2}Record [:doc_test.Example] [/lib/doc/test.lua:11] [@Ty<Example>] ]\
document a metaty\
another line\
[{table}\
+ [*Fields]\
+ [$a]             | \\[[@int]\\] = [$4]\
]\
[{table}\
+ [*Methods, Etc]\
+ [$__docs]        | \\[[@table]\\] \
+ [$__fields]      | \\[[@table]\\] \
+ [$__index]       | \\[[@Ty<Example>]\\] [/lib/doc/test.lua:11]\
+ [$__name]        | \\[[@string]\\] \
+ [$__newindex]    | \\[[@function]\\] [/lib/metaty/metaty.lua:180]\
+ [$method]        | \\[[@function]\\] [/lib/doc/test.lua:12]\
]"

  T.assertEq(expect,     doc.docstr(M.Example))
end)

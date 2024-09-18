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

local pkglib = require'pkglib'
local mty = require'metaty'
local ds = require'ds'
local T = require'civtest'
local doc = require'doc'

local str = mty.tostring

T.assertEq(mod.__newindex, getmetatable(M.Example).__newindex)
T.assertEq('doc_test.Example',    PKG_NAMES[M.Example])
T.assertEq('cmd/doc/test.lua:11', PKG_LOC[M.Example])

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



local doFmt = function(fn, obj)
  local f = mty.Fmt{}
  fn(f, obj)
  return table.concat(f)
end

T.test('doc fn', function()
  local res = doc.construct(M.exampleFn, nil, 0)
  T.assertEq(
    '[$doc_test.exampleFn] | \\[function\\] [/cmd/doc/test.lua:5]',
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.exampleFn, nil, 1)
  T.assertEq('Function', res.docTy)
  T.assertEq(
"[{h3}Function [{style=api}doc_test.exampleFn] [/cmd/doc/test.lua:5]]\
document a fn\
another line\
\
[$M.exampleFn = function() end]",
    doFmt(doc.fmtDoc, res))
end)


T.test('doc ty', function()
  local res = doc.construct(M.Example, nil, 0)
  T.assertEq(
    "[$doc_test.Example] | \\[Ty<Example>\\] [/cmd/doc/test.lua:11]",
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.Example, nil, 1)
  T.assertEq(
"[{h3}Record [{style=api}doc_test.Example] [/cmd/doc/test.lua:11]]\
document a metaty\
another line\
\
[*Fields: ] [{table}\
+ [$a]             | \\[int\\] = [$4]\
]\
[*Values: ] [{table}\
+ [$__docs]        | \\[table\\] \
+ [$__fields]      | \\[table\\] \
+ [$__name]        | \\[string\\] \
]\
[*Records: ] [{table}\
+ [$__index]       | \\[Ty<Example>\\] [/cmd/doc/test.lua:11]\
]\
[*Methods: ] [{table}\
+ [$__newindex]    | \\[function\\] [/lib/metaty/metaty.lua:180]\
+ [$method]        | \\[function\\] [/cmd/doc/test.lua:12]\
]",
    doFmt(doc.fmtDoc, res))
end)

T.test('doc module', function()
  local dir = 'cmd/doc/test/'
  local fm = dofile(dir..'docfake.lua')

  local comments, code = doc.findcode(fm)
  T.assertEq({
    "--- fake lua module for testing doc.",
    "---",
    "--- module documentation.",
  }, comments)

  local res = doFmt(doc.fmtDoc, doc.construct(fm, nil, 5))
  res = res..'\n'
  -- ds.writePath(dir..'docfake.cxt', res)
  local cxt = ds.readPath(dir..'docfake.cxt')
  T.assertEq(res, cxt)
end)

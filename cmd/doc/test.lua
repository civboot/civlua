local M = mod'doc_test'

--- document a fn
--- another line
M.exampleFn = function() return end

--- document a metaty
--- another line
M.Example  = require'metaty''Example'{
  'a [int]', a=4,
}
M.Example.method = function() end

METATY_CHECK = true

local pkglib = require'pkglib'
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local T = require'civtest'
local doc = require'doc'

T.assertEq(mod.__newindex, getmetatable(M.Example).__newindex)
T.assertEq('doc_test.Example',    PKG_NAMES[M.Example])
T.assertEq('cmd/doc/test.lua:11', PKG_LOC[M.Example])

local rmPaths = function(str) return str:gsub('(/.-):%d+', '%1:000') end
T.assertEq('blah blah foo/bar.baz:000 blah blah',
  rmPaths('blah blah foo/bar.baz:100 blah blah'))
T.assertEq('a b c/cmd/doc/test.lua:000 def',
  rmPaths('a b c/cmd/doc/test.lua:11 def'))

local doFmt = function(fn, obj)
  local f = fmt.Fmt{}
  fn(f, obj)
  return rmPaths(table.concat(f))
end


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
  T.assertEq({"M.exampleFn = function() return end"}, code)

  com, code = doc.findcode(M.Example)
  T.assertEq('--- document a metaty', com[1])
  T.assertEq('--- another line',      com[2])
  T.assertEq([[M.Example  = require'metaty''Example'{]], code[1])
  T.assertEq([[  'a [int]', a=4,]], code[2])
  T.assertEq('}', code[3])
end)


T.test('doc fn', function()
  local res = doc.construct(M.exampleFn, nil, 0)
  T.assertEq(
    '[$doc_test.exampleFn] | \\[function\\] [/cmd/doc/test.lua:000]',
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.exampleFn, nil, 1)
  T.assertEq('Function', res.docTy)
  T.assertEq(
"[{h3}Function [:doc_test.exampleFn][$() -> nil] [/cmd/doc/test.lua:000]]\
document a fn\
another line",
    doFmt(doc.fmtDoc, res))
end)


T.test('doc ty', function()
  local res = doc.construct(M.Example, nil, 0)
  T.assertEq(
    "[$doc_test.Example] | \\[Ty<Example>\\] [/cmd/doc/test.lua:000]",
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.Example, nil, 1)
  T.assertEq(
"[{h3}Record [:doc_test.Example] [/cmd/doc/test.lua:000]]\
document a metaty\
another line\
\
[*Fields: ] [{table}\
+ [$doc_test.Example.a] | \\[int\\] = [$4]\
]\
[*Values: ] [{table}\
+ [$doc_test.Example.__docs] | \\[table\\] \
+ [$doc_test.Example.__fields] | \\[table\\] \
+ [$doc_test.Example.__name] | \\[string\\] \
]\
[*Records: ] [{table}\
+ [$doc_test.Example.__index] | \\[Ty<Example>\\] [/cmd/doc/test.lua:000]\
]\
[*Methods: ] [{table}\
+ [$doc_test.Example.__newindex] | \\[function\\] [/lib/metaty/metaty.lua:000]\
+ [$doc_test.Example.method] | \\[function\\] [/cmd/doc/test.lua:000]\
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
  -- ds.writePath(dir..'docfake.cxt', res) -- uncomment to update, then check diff!
  local cxt = ds.readPath(dir..'docfake.cxt')
  T.assertEq(cxt, res)
end)

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

local pkglib = require'pkglib'
local mty = require'metaty'
local fmt = require'fmt'
local pth = require'ds.path'
local T = require'civtest'
local doc = require'doc'

T.eq(mod.__newindex, getmetatable(M.Example).__newindex)
T.eq('doc_test.Example',    PKG_NAMES[M.Example])
T.eq('cmd/doc/test.lua:11', PKG_LOC[M.Example])

local rmPaths = function(str) return str:gsub('(/.-):%d+', '%1:000') end
T.eq('blah blah foo/bar.baz:000 blah blah',
  rmPaths('blah blah foo/bar.baz:100 blah blah'))
T.eq('a b c/cmd/doc/test.lua:000 def',
  rmPaths('a b c/cmd/doc/test.lua:11 def'))

local doFmt = function(fn, obj)
  local f = fmt.Fmt{}
  fn(f, obj)
  return rmPaths(table.concat(f))
end


-- This was used to craft the for documentation
T.pairs = function()
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
end

T.findcode = function()
  local com, code = doc.findcode(M.exampleFn)
  T.eq({"--- document a fn", "--- another line"}, com)
  T.eq({"M.exampleFn = function() return end"}, code)

  com, code = doc.findcode(M.Example)
  T.eq('--- document a metaty', com[1])
  T.eq('--- another line',      com[2])
  T.eq([[M.Example  = require'metaty''Example'{]], code[1])
  T.eq([[  'a [int]', a=4,]], code[2])
  T.eq('}', code[3])
end


T.doc_fn = function()
  local res = doc.construct(M.exampleFn, nil, 0)
  T.eq(
    "[$doc_test.exampleFn] | \\[[$() -> nil]\\] ([{path=cmd/doc/test.lua:000}src])",
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.exampleFn, nil, 1)
  T.eq('Function', res.docTy)
  T.eq(
"[{h3}Function [:doc_test.exampleFn][$() -> nil] ([{i path=cmd/doc/test.lua:000}src])]\
document a fn\
another line",
    doFmt(doc.fmtDoc, res))
end


T.doc_ty = function()
  local res = doc.construct(M.Example, nil, 0)
  T.eq(
    "[$doc_test.Example] | \\[Ty<Example>\\] ([{path=cmd/doc/test.lua:000}src])",
    doFmt(doc.fmtDocItem, res))

  local res = doc.construct(M.Example, nil, 1)
  T.eq(
"[{h3}Record [:doc_test.Example] ([{i path=cmd/doc/test.lua:000}src])]\
document a metaty\
another line\
\
[*Fields: ] [{table}\
+ [$doc_test.Example.a] | \\[int\\] = [$4]\
]\
[*Values: ] [{table}\
+ [$doc_test.Example.__docs] | \\[table\\] \
+ [$doc_test.Example.__fieldIds] | \\[table\\] \
+ [$doc_test.Example.__fields] | \\[table\\] \
+ [$doc_test.Example.__name] | \\[string\\] \
]\
[*Records: ] [{table}\
+ [$doc_test.Example.__index] | \\[Ty<Example>\\] ([{path=cmd/doc/test.lua:000}src])\
]\
[*Methods: ] [{table}\
+ [$doc_test.Example.__fmt] | \\[function\\] ([{path=lib/metaty/metaty.lua:000}src])\
+ [$doc_test.Example.__newindex] | \\[function\\] ([{path=lib/metaty/metaty.lua:000}src])\
+ [$doc_test.Example.__tostring] | \\[function\\] ([{path=lib/metaty/metaty.lua:000}src])\
+ [$doc_test.Example.method] | \\[function\\] ([{path=cmd/doc/test.lua:000}src])\
]",
    doFmt(doc.fmtDoc, res))
end

T.doc_module = function()
  local dir = 'cmd/doc/test/'
  local fm = dofile(dir..'docfake.lua')

  local comments, code = doc.findcode(fm)
  T.eq({
    "--- fake lua module for testing doc.",
    "---",
    "--- module documentation.",
  }, comments)

  local res = doFmt(doc.fmtDoc, doc.construct(fm, nil, 5))
  res = res..'\n'
  pth.write(dir..'docfake.cxt', res) -- uncomment to update, then check diff!
  local cxt = pth.read(dir..'docfake.cxt')
  T.eq(cxt, res)
end

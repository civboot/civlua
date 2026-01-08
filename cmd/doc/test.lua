local mty = require'metaty'
--- Example module
local Tm = mty.mod'TestMod'
--- Example function documentation.
Tm.exampleFn = function(a) --> b
end
--- Example record documentation.
Tm.A = mty'A' {
  'a [int]: example field doc',
    a = 'default',
  'b',
}
--- Example method documentation.
function Tm.A:exampleMeth(b) --> c
end

local M = require'doc'
local T = require'civtest'
local ds = require'ds'

local Dc = M.Doc

local concat = table.concat

T'find' do
  T.eq(M,         M.tryfind'doc')
  T.eq(M.tryfind, M.tryfind'doc.tryfind')
end

T'fnsig' do
  local d = Dc{}
  T.eq({'(a) -> b'},       {d:fnsig{'M.a = function(a) --> b'}})
  T.eq({'(a) -> b'},       {d:fnsig{'function M.a(a) --> b'}})
  T.eq({'(a) -> b', true}, {d:fnsig{'function M:a(a) --> b'}})
end

T'extractCode' do
  local d = Dc{}
  local cmt, code = d:extractCode(M.find)
  T.eq({'Find the object/name.'},        cmt)
  T.eq({"function M.find(obj) --> any"}, code)
  T.eq('(obj) -> any', d:fnsig(code))

  local cmt, code = d:extractCode(d.extractCode)
  T.eq({}, cmt)
  T.eq({"function M.Doc:extractCode(loc) --> (commentLines, codeLines)"},
       code)
  T.eq({"(loc) -> (commentLines, codeLines)", true}, {d:fnsig(code)})

  local cmt, code = d:extractCode(Dc.hdrlevel)
  T.eq({"function M.Doc:hdrlevel(add) --> int"}, code)
  T.eq({'(add) -> int', true}, {d:fnsig(code)})
end

T'Doc' do
  local d = Dc{}
  local function testDc(cxt, html)
    T.eq(cxt, concat(d)); ds.clear(d)
    if html then
      error'todo'
    end
  end
  d:link'foo.com';          testDc'[<foo.com>]'
  d:link('foo.com', 'foo'); testDc'[<foo.com>foo]'
  d:code('blah.blah');      testDc'[$blah.blah]'
end

local Tm_DOC =
"[{h1 name=TestMod}Mod TestMod]\
Example module\
\
[*Types] [+\
* [*TestMod.A]\
]\
\
[*Functions] [+\
* [{*name=TestMod.exampleFn}fn exampleFn][$(a) -> b]\
  Example function documentation.\
]\
\
[{h2 name=TestMod.A}Record A]\
[+\
* [{*name=TestMod.A.a}.a] [$=\"default\"]:\
  example field doc\
* [{*name=TestMod.A.b}.b]\
]\
Example record documentation.\
\
[*Methods] [+\
* [{*name=A.exampleMeth}fn:exampleMeth][$(b) -> c]\
  Example method documentation.\
]\
"

T'mod_doc' do
  local d = Dc{}
  d:mod(Tm)
  T.eq(Tm_DOC, concat(d))
end

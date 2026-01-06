local mty = require'metaty'
--- Example module
local Tm = mty.mod'TestMod'
--- Example function documentation.
Tm.exampleFn = function(a) --> b
end
--- Example record documentation.
Tm.A = mty'A' {
  'a [int]: example field doc',
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
  local function testDc(expect)
    T.eq(expect, concat(d)); ds.clear(d)
  end
  d:link'foo.com';          testDc'[<foo.com>]'
  d:link('foo.com', 'foo'); testDc'[<foo.com>foo]'
  d:code('blah.blah');      testDc'[$blah.blah]'
end

local Dc_DOC = [=[
[{h1 name="doc.Doc"}Record Doc]
[+
* [*to] [$file]:
  file to write to.
* [*indent] [$string]
]
Object passed to __doc methods.
Aids in writing cxt.

[*Methods] [+
* [*level(f, add) -> int: current level]
  Add to the indent level and get the new value
  call with [$add=nil] to just get the current level
* [*:write(...)]
  Same as [$file:write].
* [*:flush()]
* [*:close()]
* [*:bold('[*%s]', text)]
* [*:code('[$%s]', code)]
* [*:link(link, text)]
* [*:hdrlevel(add) -> int]
* [*:header(content, name)]
* [*:extractCode(loc) -> (commentLines, codeLines)]
* [*:fnsig(code) -> (string, isMethod)]
  Extract the function signature from the lines of code.
* [*:fn(fn, cmts, name, id) -> (cmt, sig, isMethod)]
  Document the function. cmts=true also includes comments
  on new line.
* [*:mod(m)]
  Document the module.
]
]=]

T'record_doc' do
  local d = Dc{}
  Dc:__doc(d) -- write docs of itself
  T.eq(Dc_DOC, concat(d))
end

local Tm_DOC = [[
[{h1 name="TestMod"}TestMod]
Example module

[*Types] [+
* [*TestMod.A]
]

[*Functions] [+
* [*exampleFn(a) -> b]
  Example function documentation.
]

[{h2 name="TestMod.A"}Record A]
[+
* [*a] [$int]:
  example field doc
]
Example record documentation.

[*Methods] [+
* [*:exampleMeth(b) -> c]
  Example method documentation.
]
]]

T'mod_doc' do
  local d = Dc{}
  d:mod(Tm)
  T.eq(Tm_DOC, concat(d))
end

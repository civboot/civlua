-- For vim do :set tabstop=12 lcs=tab:\ \ 

local T = require'civtest'
local M = require'tv'
local mty = require'metaty'
local lf = require'ds.file'

local rep = string.rep

local assertBackslashes = function(encoded, num)
  local decoded = rep('\\', num)
  T.assertEq(encoded, M.encodeBackslashes(decoded))
  T.assertEq(decoded, M.decodeCell(encoded))
end
T.test('backslashes', function()
  assertBackslashes([[\\]],     1)
  assertBackslashes([[\2]],     2)
  assertBackslashes([[\9]],     9)
  assertBackslashes([[\9\1]],   10)
  assertBackslashes([[\9\9]],   18)
  assertBackslashes([[\9\9\1]], 19)
end)

local assertCell = function(v, encoded, serde)
  encoded = encoded or v
  T.assertEq(encoded, M.encodeCell(v,       serde and serde.ser))
  T.assertEq(v,       M.decodeCell(encoded, serde and serde.de))
end
T.test('cell', function()
  local SM = M.SerdeMap
  T.assertEq(nil,  M.decodeCell('', SM.bool.de))
  T.assertEq(true, M.decodeCell('t', SM.bool.de))
  T.assertEq(true, M.decodeCell('true', SM.bool.de))

  assertCell(nil,    '')
  assertCell(9,      '9',      SM.integer)
  assertCell(9,      '9',      SM.integer)
  assertCell(-12,    '-12',    SM.integer)
  assertCell(-12.32, '-12.32', SM.number)
  assertCell('hi'); assertCell('hi world')
  assertCell('hi\nline', 'hi\\nline')
  assertCell('hi\\9',    'hi\\\\9', SM.string)
  assertCell('hi\\1',    'hi\\\\1', SM.string)
  assertCell('hi\0',     'hi\0',    SM.string)
  assertCell([[hi\]],   [[hi\\]])
  assertCell([[hi\\\]], [[hi\3]])
  assertCell([[hi\\\
]], 'hi\\3\\n')
end)

local assertFull = function(encoded, t, names, types, smap)
  local f = io.tmpfile();
  f:write"' testfile\n"
  local enc = M.store(f, t, names, types, smap)
  T.assertEq(names, enc._names)
  T.assertEq(types, enc._types)
  f:flush(); f:seek'set'
  if encoded then
    T.assertEq(encoded, f:read'a'); f:seek'set'
  end
  local res, de = M.load(f, smap)
  f:close()
  T.assertEq(names, de._names)
  T.assertEq(types, de._types)
  T.assertEq(t, res)
end
T.test('full', function()
local names = {'a', 'b', 'c'}
local types = {'integer', 'string', 'bool'}
assertFull(
-- encoded=
[[' testfile
: integer	: string	: bool
| a	| b	| c
4	hi	true
5	bye	false
]],
-- table=
{
  {a=4, b='hi', c=true},
  {a=5, b='bye', c=false},
}, names, types)

assertFull(
-- encoded=
[[' testfile
: integer	: string	: bool
| a	| b	| c
	\	true
5		
		
]],
-- table=
{
  {     b='', c=true},
  {a=5,             },
  {                 },
}, names, types)

end) -- END FULL


METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'

local test, assertEq
mty.lrequire'civtest'

local RootSpec, Token
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = mty.lrequire'pegl'

local KW, N, NUM, HEX; mty.lrequire(testing)

local M = require'cxt'


test('simple', function()
  M.assertParse('hi there', {'hi there'})
  M.assertParse('hi there [*bob]', {
    'hi there ', {'bob', b=true},
  })
  M.assertParse('inline [ code]', {
    'inline ', {'code', code=true},
  })
  M.assertParse('multiple\n [_lines]\n\n  with [*break]', {
    'multiple\n', {'lines', u=true},
    '\n', {br=true},
    'with ', {'break', b=true},
  })
end)

test('block', function()
  M.assertParse([[
Some code:
[##
This is a bit
  of code.
]##
]], {
    "Some code:\n",
    {"This is a bit\n  of code.", code=true},
    '\n',
    {br=true},
  })
end)

-- test('parse', function()
--   local dat = ds.lines([[
-- text and [*some inline] blocks.
-- ]])
--   local cxt, p = M.parse(dat)
--   -- assertEq({}, p:toStrTokens(cxt))
--   assert(false)
-- end)

METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'

local test, assertEq
mty.lrequire'civtest'

local RootSpec, Token
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = mty.lrequire'pegl'

local KW, N, NUM, HEX; mty.lrequire(testing)

local root, T, BLANK
local M = mty.lrequire'cxt'


test('pegl easy', function()
  assertParse{dat='hi there', spec=M.src, expect={
    T'hi there', EOF
  }, root=root, dbg=true}

  assertParse{dat='hi there [*bob]', spec=M.src, expect={
    T'hi there ',
    {kind='blk',
      '[', KW'*', T'bob', ']'
    },
    EOF
  }, root=root, dbg=true}

  assertParse{dat='some [#inline code]', spec=M.src, expect={
    T'some ',
    {kind='blk',
      '[', {kind='code', KW'#', 'inline code'}, ']'
    },
    EOF
  }, root=root, dbg=true}

end)

test('pegl multiline', function()
  assertParse{dat=[[
This text
  has multiple lines
with [*some inline] blocks.

Done.
]], spec=M.src, expect={
    T'This text',
    T'  has multiple lines',
    T'with ', {kind='blk',
      '[', KW'*', T'some inline', ']',
    }, T' blocks.',
    BLANK, T'Done.', BLANK,
    EOF,
  }, root=root}
end)

test('parse', function()
  local dat = ds.lines([[
text and [*some inline] blocks.
]])
  local cxt, p = M.parse(dat)
  -- assertEq({}, p:toStrTokens(cxt))
  assert(false)
end)

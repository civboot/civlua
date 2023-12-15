METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'

local test
mty.lrequire'civtest'

local RootSpec, Token
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = mty.lrequire'pegl'

local KW, N, NUM, HEX; mty.lrequire(testing)

local T, root
local M = mty.lrequire'cxt'


test('easy', function()
  assertParse{dat='hi there', spec=M.src, expect={
    T'hi there', EOF
  }, root=root, dbg=true}

  assertParse{dat='hi there [*bob]', spec=M.src, expect={
    T'hi there ',
    {kind='ctrl',
      '[', KW'*', T'bob', ']'
    },
    EOF
  }, root=root, dbg=true}

  assertParse{dat='some [#inline code]', spec=M.src, expect={
    T'some ',
    {kind='ctrl',
      '[', {kind='code', KW'#', 'inline code'}, ']'
    },
    EOF
  }, root=root, dbg=true}

  -- assertParse{dat='hi [t url=civboot.com]there[/]', spec=M.src,
  -- expect={
  --   'hi',
  --   {kind='ctrl',
  --     KW'[',
  --     {kind='attr', 't', EMPTY},
  --     {kind='attr', 'url', KW'=', 'civboot.com'},
  --     KW']'
  --   },
  --   'there',
  --   {kind='ctrl',
  --     KW'[', {kind='attr', '/', EMPTY}, KW']'
  --   },
  --   EOF
  -- }, root=root, dbg=true}

end)

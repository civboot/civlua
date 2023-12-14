METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'
local T = require'civtest'

local RootSpec, Token
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = mty.lrequire'pegl'

local KW, N, NUM, HEX; mty.lrequire(testing)

local M = require'cxt'

local root = M.root

T.test('tokenizer', function()
  local p = pegl.Parser:new('hi [there]', M.defaultRoot())
  -- p:parse
end)

T.test('easy', function()
  assertParse{dat='hi there', spec=M.src, expect={
    'hi', 'there', EOF
  }, root=root, dbg=true}

  assertParse{dat='hi [i]there[i]', spec=M.src, expect={
    'hi',
    {kind='ctrl',
      KW'[', {kind='attr', 'i', EMPTY}, KW']'
    },
    'there',
    {kind='ctrl',
      KW'[', {kind='attr', 'i', EMPTY}, KW']'
    },
    EOF
  }, root=root, dbg=true}

  assertParse{dat='hi [t url=civboot.com]there[/]', spec=M.src,
  expect={
    'hi',
    {kind='ctrl',
      KW'[',
      {kind='attr', 't', EMPTY},
      {kind='attr', 'url', KW'=', 'civboot.com'},
      KW']'
    },
    'there',
    {kind='ctrl',
      KW'[', {kind='attr', '/', EMPTY}, KW']'
    },
    EOF
  }, root=root, dbg=true}
end)

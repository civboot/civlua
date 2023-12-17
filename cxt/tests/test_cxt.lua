METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'

local test, assertEq
mty.lrequire'civtest'

local RootSpec, Token
local testing, EMPTY, EOF
local pegl = mty.lrequire'pegl'

local KW, N, NUM, HEX; mty.lrequire(testing)

local M = require'cxt'
local html = require'cxt.html'

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
    {"\nThis is a bit\n  of code.\n", code=true},
    '\n',
    {br=true},
  })
end)

test('attrs', function()
  pegl.assertParse{dat='i', spec=M.attr, expect={
      'i', pegl.EMPTY, kind='keyval',
    },
    dbg=true
  }
  pegl.assertParse{dat='i}', spec=M.attrs,
    expect={kind='attrs',
      {'i', pegl.EMPTY, kind='keyval'},
      KW'}',
    },
    dbg=true
  }
  M.assertParse('[{i}italic] block', {
    {'italic', i=true}, ' block'
  }, true)
end)

test('html', function()
  html.assertHtml('hi [*there] bob', {'hi <b>there</b> bob'})
  html.assertHtml('hi [*there]\n  newline', {
    'hi <b>there</b>', 'newline'
  })
end)


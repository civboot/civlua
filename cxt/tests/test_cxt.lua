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
  M.assertParse('The [$inline code]', {
    'The ', {'inline code', code=true},
  })
  M.assertParse('For [$inline], [$balanced[brackets] are okay]', {
    'For ', {code=true, 'inline'}, ', ', { code=true,
      'balanced[brackets] are okay'
    },
  })
--   M.assertParse(
-- '[$inline code]. [$balanced[brackets] are allowed]', {})

  M.assertParse('multiple\n [_lines]\n\n  with [*break]', {
    'multiple\n', {'lines', u=true},
    '\n', {br=true},
    'with ', {'break', b=true},
  })
  M.assertParse('has [[ and ]] in it\nand [[foo', {
    'has ', '[ and ', '] in it\n', 'and ', '[foo',
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

test('quote', function()
  M.assertParse([[
A quote:
["We work with being,
  but non-being is what we use.

  -- Tao De Ching, Stephen Mitchel
]
]], {
    'A quote:\n',
    { quote=true,
      "We work with being,\n",
      "but non-being is what we use.\n",
      {br=true},
      "-- Tao De Ching, Stephen Mitchel\n",
    },
    '\n',
    {br=true},
  }, true)
end)

test('list', function()
  M.assertParse([[
A list:[+
* first item
* second item:[+
  * sub first
  * sub second
  ]
]
]],
  {
    'A list:', {list=true,
      {'first item\n'},
      {
        'second item:',
        { list=true,
          {'sub first\n'},
          {'sub second\n'},
        },
        '\n'
      },
    }, '\n', {br=true},
  }, true)

end)

test('html', function()
  html.assertHtml('hi [*there] bob', {'hi <b>there</b> bob'})
  html.assertHtml('hi [*there]\n  newline', {
    'hi <b>there</b>', 'newline'
  })
  html.assertHtml([[
listing:[+
* one
* two[+
  * three
  * four
  ]
]
]],{
    "listing:<ul>",
    "  <li>one",
    "  </li>",
    "  <li>two<ul>",
    "    <li>three",
    "    </li>",
    "    <li>four",
    "    </li>",
    "  </ul>",
    "  </li>",
    "</ul>",
    "<br>"
  })
end)


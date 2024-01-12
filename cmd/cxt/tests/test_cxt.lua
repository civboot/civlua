METATY_CHECK = true

local pkg = require'pkg'
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
    {"\nThis is a bit\n  of code.\n", code=true, block=true},
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

test('nested', function()
  M.assertParse([[
[+
* list item

  [##
  with inner code
  ]##
]
]],
  {
    {list=true,
      {
        "list item\n", {br=true}, {
          code=true, block=true,
          "\n",
          "with inner code\n",
        }, "\n",
      },
    }, "\n", {br=true},
  }, true)
end)


test('table', function()
  M.assertParse([[
[{table}
+ [*h]1 | h2   | h3
+ r1.1  | r1.2 | r1.3
+ r2.1  | r2.2 | r2.3
]
]],
  { -- src
    { table=true,
      { -- header
        {"", {b=true, 'h'}, '1'},
        {"h2"},
        {"h3\n"},
      },
      { -- row 1
        {"r1.1"},
        {"r1.2"},
        {"r1.3\n"},
      },
      { -- row 2
        {"r2.1"},
        {"r2.2"},
        {"r2.3\n"},
      },
    },
    '\n', {br=true},
  })
end)

test('named', function()

  M.assertParse([[
[{n=n1 href=hi.com}N1]
[@n1]
]],
  { -- src
    {'N1', name='n1', href='hi.com'},
    '\n',
    {'N1', href='hi.com'},
    '\n', {br=true},
  })

  M.assertParse([[
[{: href=hi.com}N 2]
see [@N_2], I like [<@N_2>links]
]],
  { -- src
    {'N 2', name='N_2', href='hi.com'},
    '\n', 'see ',
    {'N 2', href='hi.com'}, ', I like ',
    {'links', href='hi.com'},
    '\n', {br=true},
  })
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
      "<li>one",
      "</li>",
      "<li>two<ul>",
        "<li>three",
        "</li>",
        "<li>four",
        "</li>",
      "</ul>",
      "</li>",
    "</ul>",
    "<p>",
  })
end)


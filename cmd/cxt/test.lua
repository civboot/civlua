METATY_CHECK = true

local pkg = require'pkglib'
local mty = require'metaty'
local fmt = require'fmt'
local Mt = mod'Mt'
--- Example docs
Mt.A = mty'A' {
  'a1 [string]: docs for a1'
  ..'more docs for a1',
}

local ds  = require'ds'
local Writer = require'lines.Writer'
local M = require'cxt'
local term = require'cxt.term'
local html = require'cxt.html'

local test, assertEq; ds.auto'civtest'

local RootSpec, Token
local testing, EMPTY, EOF
local pegl = ds.auto'pegl'

local KW, N, NUM, HEX; ds.auto(testing)

test('escape', function()
  assertEq('foo \\[bar\\] \\\\ baz', M.escape'foo [bar] \\ baz')
end)

test('code', function()
  local hub = M._hasUnbalancedBrackets
  assertEq(false, hub'abc')
  assertEq(false, hub'[[a]b]')
  assertEq(true, hub'['); assertEq(true, hub']')
  assertEq(true, hub'[]]')

  local hashes = M._codeHashes
  assertEq(nil, hashes'foo bar')
  assertEq(0,   hashes'foo]bar')
  assertEq(1,   hashes'[###foo]#bar')

  assertEq('[$some [code]]', M.code'some [code]')
  assertEq('[#some [code]#', M.code'some [code')
end)

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
  M.assertParse('[$inline code].    [$balanced[brackets] are allowed]', {
    {'inline code', code=true},
    '.    ',
    {'balanced[brackets] are allowed', code=true},
  })

  M.assertParse('multiple\n [_lines]\n\n  with [*break]', {
    'multiple\n', {'lines', u=true},
    '\n', {br=true},
    'with ', {'break', b=true},
  })
  M.assertParse('has \\[ and \\] in it\n\\and \\\\foo', {
    'has ', '[ and ', '] in it\n', '\\and ', '\\foo',
  })

  M.assertParse('with \\[[@foo]\\] okay', {
    'with ', '[', {'foo', clone='foo'}, '] okay',
  })

  M.assertParse('empty [{}block works].', {'empty ', {'block works'}, '.'})
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
  })

end)

test('attrs', function()
  pegl.assertParse{dat='i', spec=M.attr, expect={
      'i', pegl.EMPTY, kind='keyval',
    },
  }
  pegl.assertParse{dat='i}', spec=M.attrs,
    expect={kind='attrs',
      {'i', pegl.EMPTY, kind='keyval'},
      KW'}',
    },
  }
  M.assertParse('[,some] [{i}italic] blocks', {
    {'some', i=true}, ' ', {'italic', i=true}, ' blocks'
  })
  M.assertParse('go to [/the/right] path', {
    'go to ',
    {'the/right', path='the/right'},
    ' path',
  })
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

* third item
]
]],
  {
    "A list:", { list=true,
      {"first item"},
      {
        "second item:", { list=true,
          {"sub first"}, {"sub second"},
        },
        "",
      },
      {"third item"},
    }, "\n"
  },
  true)

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
    { list=true,
      {
        "list item\n",
        {br=true},
        { block=true, code=true,
          "\n", "with inner code\n",
        }, ""
      },
    }, "\n"
  }, true)

end)


test('table', function()
  local doc = [[
[{table}
# [*h]1     | h2   | h3
+ [{}+r1.1] | r1.2 | r1.3
+ [{}|r2.1] | r2.2 | r2.3
]
]]
  local noIndent = M.assertParse(doc,
  { -- src
    { table=true,
      { header=true,
        {"", {b=true, 'h'}, '1'},
        {"h2"},
        {"h3"},
      },
      { row = 1,
        {"", {"+r1.1"}, ""}, -- note: trimToken* causes ""
        {"r1.2"},
        {"r1.3"},
      },
      { row = 2,
        {"", {"|r2.1"}, ""},
        {"r2.2"},
        {"r2.3"},
      },
    },
    '\n',
  })
  local docIndent = [[
[{table}
  # [*h]1 | h2   | h3
  + [{}+r1.1] | r1.2 | r1.3
  + [{}|r2.1] | r2.2 | r2.3
]
]]
  M.assertParse(docIndent, noIndent)
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
    '\n',
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
    '\n',
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
      "<li>one</li>",
      "<li>two<ul>",
        "<li>three</li>",
        "<li>four</li>",
      "</ul></li>",
    "</ul>",
  })

  html.assertHtml([[
[{table}
# [*h]1 | h2   | h3
+ r1.1  | r1.2 | r1.3
+ r2.1  | r2.2 | r2.3
]
]], {
  "<table>",
    "<tr>",
      "<th><b>h</b>1</th>",
      "<th>h2</th>",
      "<th>h3</th>",
    "</tr>",
    "<tr>",
      "<td>r1.1</td>",
      "<td>r1.2</td>",
      "<td>r1.3</td>",
    "</tr>",
    "<tr>",
      "<td>r2.1</td>",
      "<td>r2.2</td>",
      "<td>r2.3</td>",
    "</tr>",
  "</table>",
  })

  html.assertHtml([[
Some [$inline code] and: [##
code 1
code 2
]##
next line.
]], {
  "Some <code>inline code</code> and: <code class=\"block\">code 1",
  "code 2</code>",
  "next line."
})
end)

test('term', function()
  local W = Writer; local w = W{}
  local sty = term{
    '[$code] not code',
    out=fmt.Fmt{to=w}
  }
  assertEq(W{'code not code', ''}, w)

  ds.clear(w)
  local _, node, p = term.convert([[
[{h1}Heading 1]
Some text
... more text

Code:
[{## lang=lua}
function foo() return 'hello world' end
]##

[*bold] [,italic] [/path/to/thing] [+
  * item 1
  * item 2 [$with code]
]
the end
]], sty)
local expect =
"########################################\
# Heading 1\
Some text\
... more text\
\
Code:\
\
function foo() return 'hello world' end\
\
bold italic path/to/thing \
  * item 1\
  * item 2 with code\
the end\
"
  assertEq(expect, table.concat(w, '\n'))

  ds.clear(w)
local _, node, p = term.convert(
--"[{h1}[:doc_test] [/lib/doc/test.lua:1] [@Ty<doc_test>]]\
"[{h1}[:doc_test] [/lib/doc/test.lua:1] [@Ty<doc_test>] ]\
[{table}\
+ [*Methods, Etc]\
+ [:Example]      [@Ty<Example>]       | [/lib/doc/test.lua:11]\
+ [:__name]       [@string]            | \
]", sty)
  local expect =
"########################################\
# doc_test lib/doc/test.lua:1 Ty<doc_test> \
\
  + Methods, Etc\
  + Example      Ty<Example>\9lib/doc/test.lua:11\
  + __name       string\9 "
  assertEq(expect, table.concat(w, '\n'))
end)


test('doc', function()
  -- local d = require'doc'.docstr(Mt.A)
  -- M.parse(d)
end)

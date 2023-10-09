METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'
local T = require'civtest'

local RootSpec, Token
local testing, EMPTY, EOF, assertParse, assertParseError, parseStrs
local pegl = mty.lrequire'pegl'

local num, str, exp1, exp, field, varset
local root, src
local M = mty.lrequire'pegl.lua'

local KW, N, NUM, HEX; mty.lrequire(testing)
local SRC = function(...) return {..., EMPTY, EMPTY, EOF} end

T.test('easy', function()
  assertParse{dat='42  0x3A', spec={num, num}, expect={
    NUM'42', HEX'0x3A',
  }, root=root}
  assertParse{dat='  nil\n', spec={exp1}, expect=KW('nil')}
  assertParse{
    dat='true  \n false', spec={exp1, exp1},
    expect={KW('true'), KW('false')}}

  -- use exp instead
  assertParse{dat='  nil\n', spec={exp}, expect=KW('nil')}
end)

T.test('str', function()
  assertParse{dat=' "hi there" ', spec={str},
    expect={kind='doubleStr', '"hi there"'}}
  assertParse{dat=[[  'yo\'ya'  ]], spec={str},
    expect={kind='singleStr', [['yo\'ya']]}}
  assertParseError{dat=[[  'yo\'ya"  ]], spec={exp},
    errPat='Expected singleStr, reached end of line'
  }
  assertParse{dat=[[  'single'  ]], spec={str},
    expect={kind='singleStr', [['single']]}}
end)

-- TODO: Not sure where '.' is going
-- T.test('decimal', function()
--   assertParse{dat='-42 . 3343', spec={num}, expect={
--     NUM{neg=-1, 42,3343}
--   }, root=root, dbg=true}
-- end)


T.test('field', function()
  assertParse{dat=' 44 ',     spec={field},
    expect={kind='field', NUM'44'}}
  assertParse{dat=' hi ',     spec={field},
    expect={kind='field', {kind='name', 'hi'}}}
  assertParse{dat=' hi="x" ', spec={field},
    expect={kind='field',
      {kind='name', 'hi'}, KW('='), {kind='doubleStr', '"x"'},
    }
  }
  assertParse{dat='[hi] = 4', spec={field},
    expect = {
      kind='field',
      KW('['), {'hi', kind='name'}, KW(']'),
      KW('='), NUM'4',
    }
  }
end)

T.test('table', function()
  assertParse{dat='{}', spec={exp}, 
    expect={kind='table',
      KW('{'), EMPTY, KW('}'),
    },
  }
  assertParse{dat='{4}', spec={exp},
    expect={kind='table',
      KW('{'),
      {kind='field', NUM'4'},
      EMPTY,
      KW('}'),
    },
  }
  assertParse{dat='{4, x="hi"}', spec={exp},
    expect={ kind='table',
      KW('{'),
      {kind='field', NUM'4'},
      KW(','),
      {kind='field',
        {kind='name', 'x'}, KW('='), {kind='doubleStr', '"hi"'}},
      EMPTY,
      KW('}'),
    },
  }
end)

T.test('fnValue', function()
  assertParse{dat='function() end', spec={exp},
    expect = { kind='fnvalue',
      KW('function'), KW('('), EMPTY, KW(')'),
      EMPTY,
      KW('end'),
    },
  }
end)

T.test('expression', function()
  assertParse{dat='x+3', spec=exp,
    expect={N'x', KW'+', NUM'3'},
  }
  assertParse{dat='x()+3', spec=exp,
    expect= {
      N"x", {kind='call',
        KW"(", EMPTY, KW")",
      }, KW"+", NUM'3'
    },
  }
end)

T.test('require', function()
  assertParse{dat='local F = require"foo"', spec=src,
    expect = SRC(
      { kind='varlocal',
        KW('local'),
        {kind='name', 'F'},
        KW('='),
        {kind='name', 'require'},
        {kind='doubleStr', '"foo"'},
      }
    ),
  }
end)

T.test('varset', function()
  local code1 = 'a = 7'
  local expect1 = {kind='varset', N'a', KW'=', NUM'7',
  }
  assertParse{dat=code1, spec=varset, expect=expect1}
end)

T.test('comment', function()
  local expect = SRC(
    {kind='varset',
      N"x", KW"=", {kind="table",
        KW"{", EMPTY, KW"}",
      },
    })
  assertParse{dat='x = --line\n  {}', spec=src,
    expect=expect, root=root,
  }
  assertParse{dat='x = --[[block]]{}', spec=src,
    expect = expect, root=root,
  }
  assertParse{dat='x\n=\n--[[\nblock\n]]\n{}--hi\n--EOF', spec=src,
    expect = expect, root=root,
  }
end)

T.test('function', function()
  assertParse{ spec=src, root=root,
    dat=[[ local function f(a) end ]],
    expect = {
      {kind="fnlocal",
        KW"local", KW"function", N"f", KW"(", N"a", KW")", EMPTY, KW"end",
      }, EMPTY, EMPTY, EOF
    },
  }
end)

T.test('fncall', function()
  local r = assertParse{dat='foo(4)', spec=src, root=root,
    expect = SRC({ kind="stmtexp",
      N"foo", {kind='call',
        KW"(", NUM'4', KW")",
      },
    })
  }
  r = pegl.fmtParsed(r, root)
  T.assertEq([[
{
  {
    N"foo", {
      KW"(", NUM{4}, KW")", kind="call"
    }, kind="stmtexp"
  }, EMPTY, EMPTY, EOF
}]], r)

  assertParse{dat='foo({__tostring=4})', spec=src, root=root,
    expect = SRC({ kind="stmtexp",
      N"foo", { kind='call',
        KW"(", { kind="table",
          KW"{",
            {N"__tostring", KW"=", NUM'4', kind="field"}, EMPTY,
          KW"}",
        }, KW")",
      },
    })
  }
end)

T.test('if elseif else', function()
  assertParse{dat='if n==nil then return "" end', spec=src, root=root,
    expect=SRC(
    { kind='if',
      KW"if",
        { kind='cond',
          N"n", KW"==", KW"nil",
        }, KW"then", { kind='return',
        KW"return", {
          "\"\"", kind="doubleStr"
        },
      }, EMPTY, EMPTY, KW"end",
    })
  }
end)

T.test('src1', function()
  local code1 = 'a.b = function(y, z) return y + z end'
  local expect1 = SRC({kind='varset',
    N'a', KW'.', N'b', KW'=', {kind='fnvalue',
      KW'function', KW'(', N'y', KW',', N'z', KW')',
      {kind='return', KW'return', N'y', KW'+', N'z'},
      EMPTY,
      KW'end',
    },
  })
  assertParse{dat=code1, spec=src, expect=expect1}

  local code2 = code1..'\nx = y'
  local expect2 = ds.copy(expect1)
  table.remove(expect2) -- EOF
  table.remove(expect2) -- EMPTY
  ds.extend(expect2, SRC({kind='varset',
    N'x', KW'=', N'y',
  }))
  assertParse{dat=code2, spec=src, expect=expect2}
end)

local function extendExpectAssert(code, spec, expect, extend, dbg)
  T.assertEq(EOF, table.remove(expect))
  T.assertEq(EMPTY, table.remove(expect))
  T.assertEq(EMPTY, table.remove(expect))
  ds.extend(expect, extend)
  table.insert(expect, EMPTY)
  table.insert(expect, EMPTY)
  table.insert(expect, EOF)
  assertParse{dat=code, spec=spec, expect=expect, root=root, dbg=dbg}
end

T.test('src2', function()
  local code = '-- this is a comment\n--\n-- and another comment\n'
  assertParse{dat=code, spec=src, expect={EMPTY, EOF}, root=root}

  local expect = {EMPTY, EMPTY, EOF}
  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {{kind='varlocal',
    KW'local', N'add', KW'=', N'table', KW'.', N'insert'
  }})

  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {EMPTY, {kind='varlocal',
    KW'local', N'add', KW'=', N'table', KW'.', N'insert'
  }})

  local code = code..'local last = function(t) return t[#t] end\n'
  extendExpectAssert(code, src, expect, {EMPTY, {kind='varlocal',
    KW'local', N'last', KW'=',
      {kind='fnvalue',
        KW'function', KW'(', N't', KW')',
        {kind='return',
          KW'return', N't', {kind='index',
            KW'[', KW'#', N't', KW']',
          }
        },
        EMPTY, KW'end',
      },
    },
  })
end)

T.test('error', function()
  T.assertErrorPat(
    'stack: block -> stmt -> fnlocal -> fnbody '
    ..'-> block -> stmt -> varset -> exp -> op2exp -> exp -> exp1 -> table\n'
    ..'parser expected: }',
    function()
      parseStrs([[
        local function x()
          x = 1 + {2 3} -- '2 3' is invalid
        end
      ]], src, RootSpec{dbg=false})
    end, --[[plain]] true)
end)

local function testLuaPath(path)
  local f = io.open(path, 'r')
  local text = f:read'*a'
  f:close()
  assertParse{dat=text, spec=src, root=root, parseOnly=true}
end

T.test('parseSrc', function()
  testLuaPath('./patience/patience.lua')
  -- TODO: it doesn't like doc[[...]](thing)
  -- testLuaPath('./pegl/pegl.lua')
  testLuaPath('./pegl/pegl/lua.lua')
end)

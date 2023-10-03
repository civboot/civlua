local ds = require'ds'
local T = require'civtest'
T.grequire'pegl'
T.grequire'pegl.lua'

local KW = function(kw) return {kw, kind=kw} end
local EMPTY, EOF = {kind='Empty'}, {kind='EOF'}

local N = function(n) return {kind='name', n} end

T.test('easy', function()
  assertParse{dat='42  0x3A', spec={num, num}, expect={
    {kind='dec', '42'},
    {kind='hex', '0x3A'},
  }}
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


T.test('field', function()
  assertParse{dat=' 44 ',     spec={field},
    expect={kind='field', {kind='dec',  '44'}}}
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
      KW('='), {'4', kind='dec'},
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
      {kind='field', {kind='dec', '4'}},
      EMPTY,
      KW('}'),
    },
  }
  assertParse{dat='{4, x="hi"}', spec={exp},
    expect={ kind='table',
      KW('{'),
      {kind='field', {kind='dec', '4'}},
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

T.test('require', function()
  assertParse{dat='local F = require"foo"', spec=src, 
    expect = {
      { kind='varlocal',
        KW('local'),
        {kind='name', 'F'},
        KW('='),
        {kind='name', 'require'},
        {kind='doubleStr', '"foo"'},
      },
      EOF,
    },
  }
end)

T.test('varset', function()
  local code1 = 'a = 7'
  local expect1 = {kind='varset', N'a', KW'=', {kind='dec', '7'},
  }
  assertParse{dat=code1, spec=varset, expect=expect1}
end)

T.test('comment', function()
  assertParse{dat='x = --line\n  {}', spec=src,
    expect = {
      {kind='varset',
        N"x", KW"=", {kind="table",
          KW"{", EMPTY, KW"}",
        },
      },
      EOF,
    },
    dbg=true,
  }
end)

T.test('src1', function()
  local code1 = 'a.b = function(y, z) return y + z end'
  local expect1 = {
    {kind='varset',
      N'a', KW'.', N'b', KW'=', {kind='fnvalue',
        KW'function', KW'(', N'y', KW',', N'z', EMPTY, KW')',
        {kind='return', KW'return', N'y', KW'+', N'z'},
        EMPTY,
        KW'end',
      },
    },
    EOF,
  }
  assertParse{dat=code1, spec=src, expect=expect1}

  local code2 = code1..'\nx = y'
  local expect2 = ds.copy(expect1)
  table.remove(expect2) -- EOF
  ds.extend(expect2, {
    {kind='varset',
      N'x', KW'=', N'y',
    },
    EOF,
  })
  assertParse{dat=code2, spec=src, expect=expect2}
end)

local function extendExpectAssert(code, spec, expect, extend, dbg)
  T.assertEq(EOF, table.remove(expect))
  ds.extend(expect, extend)
  table.insert(expect, EOF)
  assertParse{dat=code, spec=spec, expect=expect, dbg=dbg}
end

T.test('src2', function()
  local code = '-- this is a comment\n--\n-- and another comment\n'
  local expect = {
    -- {'-- this is a comment',   kind='comment'},
    -- {'--',                     kind='comment'},
    -- {'-- and another comment', kind='comment'},
    EOF,
  }
  assertParse{dat=code, spec=src, expect=EOF}

  expect = {EOF}
  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {{kind='varlocal',
    KW'local', N'add', KW'=', N'table', KW'.', N'insert'
  }})

  local code = code..'\nlocal add = table.insert\n'
  extendExpectAssert(code, src, expect, {{kind='varlocal',
    KW'local', N'add', KW'=', N'table', KW'.', N'insert'
  }})

  local code = code..'local last = function(t) return t[#t] end\n'
  extendExpectAssert(code, src, expect, {{kind='varlocal',
    KW'local', N'last', KW'=',
      {kind='fnvalue',
        KW'function', KW'(', N't', EMPTY, KW')',
        {kind='return',
          KW'return', N't', {kind='index',
            KW'[', KW'#', N't', KW']',
          }
        },
        EMPTY, KW'end',
      },
    },
  })
local add = table.insert

end)

local function testLuaPath(path)
  local f = io.open(path, 'r')
  local text = f:read'*a'
  f:close()
  assertParse{dat=text, spec=src,
    expect={
    },
  }
end

T.test('parseSrc', function()
  -- testLuaPath('./patience/patience.lua')
end)

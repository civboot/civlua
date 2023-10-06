METATY_CHECK = true

local mty = require'metaty'
local T = require'civtest'
local ds = require'ds'
local Set = ds.Set

local RootSpec, Key
local Pat, Or, Not, Many, Maybe, Seq
local Empty, Eof, PIN, UNPIN
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = mty.lrequire'pegl'

local KW, N = testing.KW, testing.N

T.test('keywords', function()
  assertParse{
    dat='hi there bob',
    spec=Seq{'hi', 'there', 'bob', Eof},
    expect={KW('hi'), KW('there'), KW('bob'), EOF}
  }

  -- keyword search looks for token break
  assertParse{
    dat='hitherebob',
    spec=Seq{'hi', 'there', 'bob', Eof},
    expect=nil,
  }

  assertParse{
    dat='hi+there',
    spec=Seq{'hi', '+', 'there', Eof},
    expect={KW('hi'), KW('+'), KW('there'), EOF},
  }
end)

T.test('key', function()
  local kws = Key{{'hi', 'there', 'bob'}, kind='kw'}
  assertParse{
    dat='hi there', spec={kws, kws},
    expect={{kind='kw', 'hi'}, {kind='kw', 'there'}},
  }
  local kws = Key{{'x', ['+']={true, '+'}}}
  assertParse{
    dat='x + x ++ x', spec={kws, kws, kws, kws, kws},
    expect={KW'x', KW'+', KW'x', KW'++', KW'x'},
  }
end)

T.test('pat', function()
  assertParse{
    dat='hi there bob',
    spec={'hi', Pat('%w+'), 'bob', Eof},
    expect={KW('hi'), 'there', KW('bob'), EOF},
  }
end)

T.test('or', function()
  assertParse{
    dat='hi +-',
    spec={'hi', Or{'-', '+'}, Or{'-', '+', Empty}, Or{'+', Empty}, Eof},
    expect={KW('hi'), KW('+'), KW('-'), EMPTY, EOF},
  }
end)

T.test('many', function()
  assertParse{
    dat='hi there bob',
    spec=Seq{Many{Pat('%w+'), kind='words'}},
    expect={'hi', 'there', 'bob', kind='words'},
  }
end)

T.test('pin', function()
  assertParseError{
    dat='hi there jane',
    spec={'hi', 'there', 'bob', Eof},
    errPat='expected: bob',
  }
  assertParseError{
    dat='hi there jane',
    spec={UNPIN, 'hi', 'there', PIN, 'bob', Eof},
    errPat='expected: bob',
  }

  assertParse{
    dat='hi there jane',
    spec=Seq{UNPIN, 'hi', 'there', 'bob', Eof},
    expect=nil,
  }
  assertParse{
    dat='hi there jane',
    spec=Seq{UNPIN, 'hi', 'there', 'bob', PIN, Eof},
    expect=nil,
  }
end)

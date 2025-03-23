METATY_CHECK = true

local mty = require'metaty'
local T = require'civtest'.Test()
local ds = require'ds'
local Set = ds.Set

local RootSpec, Key
local Pat, Or, Not, Many, Maybe, Seq
local Empty, Eof, PIN, UNPIN
local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = ds.auto'pegl'

local KW, N = testing.KW, testing.N

local function testEncode(d, e, ...)
  T.eq({...}, {d(e(...))})
end

T.lc_encode = function()
  local e, d = pegl.encodeSpan, pegl.decodeSpan
  testEncode(d, e, 1, 2, 3, 4)
  local bigL = 0x1FFFF
  testEncode(d, e, bigL, 1, bigL+100, 20)
end

T.keywords = function()
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
end

T.key = function()
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
end

T.pat = function()
  assertParse{
    dat='hi there bob',
    spec={'hi', Pat('%w+'), 'bob', Eof},
    expect={KW('hi'), 'there', KW('bob'), EOF},
  }
end

T.or_ = function()
  assertParse{
    dat='hi +-',
    spec={'hi', Or{'-', '+'}, Or{'-', '+', Empty}, Or{'+', Empty}, Eof},
    expect={KW('hi'), KW('+'), KW('-'), EMPTY, EOF},
  }
end

T.many = function()
  assertParse{
    dat='hi there bob',
    spec=Seq{Many{Pat'%w+', kind='words'}},
    expect={'hi', 'there', 'bob', kind='words'},
  }
end

T.pin = function()
  assertParseError{
    dat='hi there jane',
    spec={'hi', 'there', 'bob', Eof},
    errPat='expected: "bob"',
  }
  assertParseError{
    dat='hi there jane',
    spec={UNPIN, 'hi', 'there', PIN, 'bob', Eof},
    errPat='expected: "bob"',
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
end

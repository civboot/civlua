
local T = require'civtest'
local ds = require'ds'
T.grequire'pegl'
local Set = ds.Set

local KW = function(kw) return {kw, kind=kw} end
local K  = function(k)  return {k, kind='key'} end

T.test('keywords', function()
  assertParse{
    dat='hi there bob',
    spec=Seq{'hi', 'there', 'bob', EOF},
    expect={KW('hi'), KW('there'), KW('bob'), EofNode}
  }

  -- keyword search looks for token break
  assertParse{
    dat='hitherebob',
    spec=Seq{'hi', 'there', 'bob', EOF},
    expect=nil,
  }

  assertParse{
    dat='hi+there',
    spec=Seq{'hi', '+', 'there', EOF},
    expect={KW('hi'), KW('+'), KW('there'), EofNode},
    root=RootSpec{punc1=Set{'+'}},
  }
end)

T.test('key', function()
  local kws = Key{keys=Set{'hi', 'there', 'bob'}, kind='kw'}
  assertParse{
    dat='hi there', spec={kws, kws},
    expect={{kind='kw', 'hi'}, {kind='kw', 'there'}},
  }
end)

T.test('pat', function()
  assertParse{
    dat='hi there bob',
    spec={'hi', Pat('%w+'), 'bob', EOF},
    expect={KW('hi'), 'there', KW('bob'), EofNode},
  }
end)

T.test('or', function()
  assertParse{
    dat='hi +-',
    spec={'hi', Or{'-', '+'}, Or{'-', '+', Empty}, Or{'+', Empty}, EOF},
    expect={KW('hi'), KW('+'), KW('-'), EmptyNode, EofNode},
    root=RootSpec{punc1=Set{'+', '-'}},
  }
end)

T.test('many', function()
  assertParse{
    dat='hi there bob',
    spec=Seq{Many{Pat('%w+'), kind='words'}},
    expect={'hi', 'there', 'bob', kind='words'},
    dbg=true,
  }
end)

T.test('pin', function()
  assertParseError{
    dat='hi there jane',
    spec={'hi', 'there', 'bob', EOF},
    errPat='expected: bob',
  }
  assertParseError{
    dat='hi there jane',
    spec={UNPIN, 'hi', 'there', PIN, 'bob', EOF},
    errPat='expected: bob',
  }

  assertParse{
    dat='hi there jane',
    spec=Seq{UNPIN, 'hi', 'there', 'bob', EOF},
    expect=nil,
  }
  assertParse{
    dat='hi there jane',
    spec=Seq{UNPIN, 'hi', 'there', 'bob', PIN, EOF},
    expect=nil,
  }
end)

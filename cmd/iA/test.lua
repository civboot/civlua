local ds = require'ds'
local iA = require'iA'
local piA = require'iA.parse'
local T = require'civtest'
local info = require'ds.log'.info
local pegl = require'pegl'

local C = iA.core

local testing, EMPTY, EOF, assertParse, assertParseError
  = mty.from(pegl, 'testing, EMPTY, EOF, assertParse, assertParseError')

local KW, N, TY, NUM, HEX = mty.from(testing, 'KW, N, TY, NUM, HEX')

T'expr1'; do
  -- literal 42
  local tok = assertParse{dat='42', spec=pegl.common.base10,
    expect=NUM{42},
  }
  T.eq(iA.Literal{42, ty=C.U1}, piA.toIa(tok))

  -- variable declaration
  tok = assertParse{dat='A a: UInt', spec={piA.var},
    expect={kind='var',
      EMPTY, {kind='reg', 'A'}, N'a',
      {kind='tySpec', KW':', TY'UInt'},
    },
  }
  T.eq(iA.Var{imm=true, reg='A', name='a', ty='UInt'},
       piA.toIa(tok))

  -- assignment
  tok = assertParse{dat='a+= 3', spec={piA.rvalue},
    expect={kind='eq',
      N'a', {'+=', kind='eqOp'}, NUM{3}
    },
  }
  T.eq(iA.Expr1{
      kind='EQ1', op='ADD', iA.Var{name='a'}, iA.literal(3),
    }, piA.toIa(tok))
end

T'Cmp'; do
  local tok = assertParse{dat='a==3', spec=piA.stmt,
    expect={kind='cmp', N'a', KW'==', NUM{3},
    },
  }
end

T'Block'; do
  local tok = assertParse{dat='true false a=2',
    spec=piA.block, expect={kind='block',
      KW'true', KW'false', {kind='assign',
        N'a', KW'=', NUM{2}
      }
    },
  }
  T.eq({
    iA.literal(1),
    iA.literal(0),
    iA.Assign{iA.Var{name='a'}, eq=iA.literal(2)},
  }, piA.toIa(tok))
end

T'If'; do
  local tok = assertParse{dat='goto loc', spec=piA.stmt,
    expect={kind='goto',
      KW'goto', N'loc',
    },
  }
  T.eq(iA.Goto{to='loc'}, piA.toIa(tok))

  tok = assertParse{dat='if true do goto loc end', spec=piA.stmt,
    expect={kind='if',
      KW'if', {kind='block', KW'true'}, KW'do',
      {kind='block',
        {kind='goto', KW'goto', N'loc'},
      }, EMPTY, KW'end'
    },
  }
  T.eq(iA.If{
    iA.CondBlock{cond={iA.literal(1)}, iA.Goto{to="loc"}},
  }, piA.toIa(tok))

  -- tok = assertParse{parseOnly=true, spec=piA.stmt,
  --   dat=[[
  --     if false    do goto loc
  --     elif a == 3 do a += 3
  --     else           a = 0  end
  --   ]]
  -- }
end

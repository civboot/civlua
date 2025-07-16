METATY_CHECK = true

local ds = require'ds'
local iA = require'iA'
local piA = require'iA.parse'
local T = require'civtest'
local info = require'ds.log'.info

local C = iA.core

local testing, EMPTY, EOF, assertParse, assertParseError
local pegl = ds.auto'pegl'

local KW, N, TY, NUM, HEX; ds.auto(testing)

T.parseSmall = function()
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


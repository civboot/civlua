
local T = require'civtest'
local M = require'shim'
local p, ps, e = M.parse, M.parseStr, M.expand

T.parse = function()
  T.eq({'a', 'b', c='42'},  ps'a --c=42 b')
  T.eq({c={'1', '2'}},      ps'--c=1 --c=2')
  T.eq({c={'1', '2', '3'}}, ps'--c=1 --c=2 --c=3')

  T.eq({'-ab', c='foo'}, p{'-ab', '--c=foo'})
  T.eq({'ab', '--', '--bob=1', c='foo'},
            p{'ab', '--c=foo', '--', '--bob=1'})
end

T.parseStr = function()
  T.eq({'a', 'b', c='42'}, ps'a   b --c=42')
  T.eq({c={'1', '2'}},     ps'--c=1   --c=2')
  T.eq({'-ab', c='foo'},   ps'-ab --c=foo')
end

T.expand = function()
  T.eq({'a', 'b', '--c=42'},           e{'a', 'b', c=42})
  T.eq({'a', 'b', '--c=42', '--d=hi'}, e(ps'a b --d=hi --c=42'))
end

T.list = function()
  T.eq({'12'},       M.list('12'))
  T.eq({'12', '34'}, M.list{'12', '34'})
  T.eq({'12 34'},    M.listSplit{'12 34'})
  T.eq({'12', '34'}, M.listSplit'12  \n  34')
  T.eq({'12', '34', '56', '78'},
             M.listSplit'12  \n  34 56 78')
end

T.duck = function()
  T.eq(true, M.boolean(true))
  T.eq(true, M.boolean'true')
  T.eq(true, M.boolean'yes')

  T.eq(false, M.boolean(false))
  T.eq(false, M.boolean'false')
  T.eq(nil, M.boolean(nil))
end

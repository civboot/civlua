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
  -- assertParse{
  --   dat=' hi="x" ',spec={field},
  --   expect={kind='field',
  --     {kind='name', 'hi'}, KW('='), {kind='doubleStr', '"x"'},
  --   }
  -- }
  -- assertParse('[hi] = 4', {field}, {kind='field',
  --   KW('['), {'hi', kind='name'}, KW(']'),
  --   KW('='), {'4', kind='dec'},
  -- })
end)

-- T.test('table', function()
--   assertParse('{}', {exp}, {kind='table',
--     KW('{'), EMPTY, KW('}'),
--   })
--   assertParse('{4}', {exp}, {kind='table',
--     KW('{'),
--     {kind='field', {kind='dec', '4'}},
--     EMPTY,
--     KW('}'),
--   })
--   assertParse('{4, x="hi"}', {exp}, {kind='table',
--     KW('{'),
--     {kind='field', {kind='dec', '4'}},
--     KW(','),
--     {kind='field',
--       {kind='name', 'x'}, KW('='), {kind='doubleStr', '"hi"'}},
--     EMPTY,
--     KW('}'),
--   })
-- end)
-- 
-- T.test('fnValue', function()
--   assertParse('function() end', {exp}, {kind='fnvalue',
--     KW('function'), KW('('), EMPTY, KW(')'),
--     EMPTY,
--     KW('end'),
--   }, true)
-- end)
-- 
-- T.test('require', function()
--   assertParse('local F = require"foo"', src, {
--     { kind='varlocal',
--       KW('local'),
--       {kind='name', 'F'},
--       KW('='),
--       {kind='name', 'require'},
--       {kind='doubleStr', '"foo"'},
--     },
--     EOF,
--   })
-- end)
-- 
-- T.test('src', function()
--   local code1 = 'a.b = function(y, z) return y + z end'
--   local expect1 = {
--     {kind='varset',
--       N'a', KW'.', N'b', KW'=', {kind='fnvalue',
--         KW'function', KW'(', N'y', KW',', N'z', EMPTY, KW')',
--         {kind='return', KW'return', N'y', KW'+', N'z'},
--         EMPTY,
--         KW'end',
--       },
--     },
--     EOF,
--   }
--   assertParse(code1, src, expect1)
-- 
--   local code2 = code1..'\nx = y'
--   local expect2 = copy(expect1)
--   table.remove(expect2) -- EOF
--   extend(expect2, {
--     {kind='varset',
--       N'x', KW'=', N'y',
--     },
--     EOF,
--   })
--   assertParse(code2, src, expect2)
-- 
-- end)
-- 
-- local function testLuaPath(path)
--   local f = io.open('pegl.lua', 'r')
--   local text = f:read'*a'; f:close()
--   assertParse(text, src, {
--   }, true)
-- 
-- end
-- 
-- T.test('parseSrc', function()
--   -- testLuaPath('./pegl.lua')
-- end)

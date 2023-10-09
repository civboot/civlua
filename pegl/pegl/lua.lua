-- Lua syntax in PEGL
--
-- I used http://parrot.github.io/parrot-docs0/0.4.7/html/languages/lua/doc/lua51.bnf.html
-- as a reference

local mty = require'metaty'
local ds  = require'ds'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = mty.lrequire'pegl'
local num = common.num

local M = {}

local stmt = Or{name='stmt'}

local keyW = Key{name='keyw', {
  'end', 'if', 'else', 'elseif', 'while', 'do', 'repeat', 'local', 'until',
  'then', 'function', 'return',
}}
local name = {UNPIN, Not{keyW}, Pat{'[%a_][%w_]*', kind='name'}}

-- uniary and binary operations
local op1 = Key{name='op1', {'-', 'not', '#'}}
local op2 = Key{name='op2', {
  -- standard binops
  '+', '-', '*', '/', '^', '%', 'and', 'or',
  ['.'] = {true, '.'},                      -- .    ..
  ['<'] = {true, '='}, ['>'] = {true, '='}, --  <   <=   >   >=
  ['='] = {'='}, ['~'] = {'='}              --  ==  ~=
}}

-----------------
-- Expression (exp)
-- We do exp a little different from the BNF. We create an `exp1` which is a
-- non-operated expression and then have `exp` implement a list of expression
-- operations.
--
-- The BNF uses a (confusing IMO) recursive definition which weaves
-- exp with var and prefixexp. Our definition deviates significantly because
-- you cannot do non-progressive recursion in recursive-descent (or PEG):
-- recursion is fine ONLY if you make "progress" (attempt to parse some tokens)
-- before you recurse.
--
-- exp1 ::=  nil       |  false      |  true       |  ...        |
--           Number    | unop exp    | String      | tbl         |
--           function  | name

local exp1 = Or{name='exp1', Key{{'nil', 'false', 'true'}}, Pat'%.%.%.', num}
add(exp1, {op1, exp1})

local exp = {name='exp'}    -- defined just below
add(exp1, {'(', exp, ')', kind='group'})

local call     = Or{kind='call'} -- function call (defined much later)
local methcall = {UNPIN, ':', name, PIN, call, kind='methcall'}
local index    = {kind='index',
  UNPIN, '[', Not{Or{'[', '='}}, PIN, exp, ']'
}
local postexp  = Or{name='postexp', methcall, index, call}
ds.extend(exp, {exp1, Many{ Or{postexp, {name='op2exp', op2, exp}} }})

-- laststat ::= return [explist1]  |  break
-- block    ::= {stat [`;´]} [laststat[`;´]]
local explist  = Maybe{exp, Many{',', exp}}
local return_ = {'return', explist, kind='return'}
local laststmt = Or{name='laststmt', return_, 'break'}
local block = {name='block',
  Many{stmt, Maybe(';')},
  Maybe{laststmt, Maybe(';')}
}

-----------------
-- String (+exp1)
local quoteImpl = function(p, char, pat, kind)
  p:skipEmpty()
  local l, c = p.l, p.c
  if not p:consume(char) then return end
  while true do
    local c1, c2 = p.line:find(pat, p.c)
    if c2 then
      p.c = c2 + 1
      local bs = string.match(p.line:sub(c1, c2), pat)
      if ds.isEven(#bs) then
        return Token:encode(p, l, c, p.l, c2, kind)
      end
    else
      if p.line:sub(#p.line) == '\\' then
        p:incLine(); if p:isEof() then error("Expected "..kind..", reached EOF") end
      else error("Expected "..kind..", reached end of line") end
    end
  end
end

local singleStr = function(p) return quoteImpl(p, "'", "(\\*)'", 'singleStr') end
local doubleStr = function(p) return quoteImpl(p, '"', '(\\*)"', 'doubleStr') end

local bracketStrImpl = function(p)
  local l, c = p.l, p.c
  local start = p:consume('%[=*%['); if not start then return end
  local cs, cs2 = select(2, start:lc1(p)), select(2, start:lc2(p))
  local pat = '%]'..string.rep('=', cs2 - cs - 1)..'%]'
  l, c = p.l, p.c
  while true do
    local c2, ce = p.line:find(pat, p.c) if c2 then
      local t = {kind='bracketStr', start,
        Token:encode(p, l,   c,  p.l, c2-1),
        Token:encode(p, p.l, c2, p.l, ce),
      }; p.c = ce + 1
      return t
    else
      p:incLine()
      if p:isEof() then error(
        "Expected closing "..pat:gsub('%%', '')..", reached EOF"
      )end
    end
  end
end
local bracketStr     = function(p)
  p:skipEmpty()
  return bracketStrImpl(p)
end
local str     = Or{name='str', singleStr, doubleStr, bracketStr}
add(exp1, str)


-----------------
-- Table (+exp1)

-- field ::= `[´ exp `]´ `=´ exp  |  Name `=´ exp  |  exp
local fieldsep = Key{{',', ';'}}
local field = Or{kind='field',
  {UNPIN, '[', exp, ']', '=', exp},
  {UNPIN, name, '=', exp},
  exp,
}
-- fieldlist ::= field {fieldsep field} [fieldsep]
-- tableconstructor ::= `{´ [fieldlist] `}´
local fieldlist = {name='fieldlist',
  field, Many{UNPIN, fieldsep, field}, Maybe(fieldsep)}
local tbl = {kind='table', '{', Maybe(fieldlist), '}'}
add(exp1, tbl)

-- fully define function call
-- call ::=  `(´ [explist1] `)´  |  tableconstructor  |  String
ds.extend(call, {
  {kind='call', '(', explist, ')'},
  {kind='callParen', tbl},
  {kind="callStr", str},
})

-----------------
-- Function (+exp1)

-- namelist ::= Name {`,´ Name}
-- parlist1 ::= namelist [`,´ `...´]  |  `...´
-- funcbody ::= `(´ [parlist1] `)´ block end
-- function ::= `function` funcbody
local namelist = {name, Many{',', name}}
local parlist = Or{name='parlist',
  Pat'%.%.%.',
  -- NeedLint: `...` only valid at the end
  {name, Many{ ',', Or{Pat'%.%.%.', name} }},
  Empty
}
local fnbody = {name='fnbody', '(', parlist, ')', block, 'end'}
local fnvalue = {'function', fnbody, kind='fnvalue'}
add(exp1, fnvalue)
add(exp1, name)

-----------------
-- Statement (stmt)
local elseif_  = {'elseif', {kind='cond', exp}, 'then', block, kind='elseif'}
local else_    = {'else', block, kind='else'}
local funcname = {name, Many{'.', name}, Maybe{UNPIN, ':', name}, kind='funcname'}

-- varlist `=´ explist
-- NeedLint: check that all items in first explist are var-like
local varset = {UNPIN, explist, '=', PIN, explist, kind='varset'}

ds.extend(stmt, {
  {Pat'::', name, Pat'::', kind='loc'},

  -- do block end
  {'do', block, 'end', kind='do'},

  -- while exp do block end
  {'while', exp, 'do', block, 'end', kind='while'},

  -- repeat block until exp
  {'repeat', block, 'until', exp, kind='repeat'},

  -- if exp then block {elseif exp then block} [else block] end
  {'if', {kind='cond', exp}, 'then', block,
    Many{elseif_}, Maybe(else_), 'end', kind='if'},

  -- for Name `=´ exp `,´ exp [`,´ exp] do block end
  {kind='fori',
    UNPIN, 'for', name, '=', PIN,
    exp, ',', exp, Maybe{',', exp}, 'do', block, 'end',
  },

  -- for namelist in explist1 do block end
  {kind='for',
    'for', namelist, 'in', explist, 'do', block, 'end'
  },

  -- funcname ::= Name {`.´ Name} [`:´ Name]
  -- function funcname funcbody
  {'function', funcname, fnbody, kind='fndef'},

  -- local function Name funcbody
  {UNPIN, 'local', 'function', PIN, name, fnbody, kind='fnlocal'},

  -- local namelist [`=´ explist1]
  {'local', namelist, Maybe{'=', explist}, kind='varlocal'},

  varset,

  -- catch-all exp
  -- NeedLint: only a fncall is actually valid syntax
  {exp, kind='stmtexp'},
})

local function skipComment(p)
  if not p.line then return end
  local c, c2 = p.line:find('^%-%-', p.c)
  if not c then return end
  local l = p.l; p.c = c2+1
  local t = bracketStrImpl(p)
  if t and mty.ty(t) ~= Token then
    local l1, c1 = t[1]:lc1(p)
    return Token:encode(p, l1, c1, t[#t]:lc2(p))
  end
  if t then t.c = c; return t
  else
    p.l, p.line = l, p.dat[l]
    local _, c2 = p.line:find('^.*', c2+1)
    return Token:encode(p, l, c, l, c2)
  end
end

local src = {name='src', block, Eof}
M.root = pegl.RootSpec{skipComment=skipComment}
local parse = function(dat, spec, root)
  root = root or M.root
  if not root.skipComment then root.skipComment = skipComment end
  return pegl.parse(dat, spec, root)
end

return ds.update(M, {
  src=src,
  skipComment=skipComment,
  exp=exp, exp1=exp1, stmt=stmt,
  num=num, str=str,
  field=field,
  explist=explist,
  varset=varset,
})

local G = G or _G

--- parse intermediate assembly
local M = G.mod and G.mod'iA.parse' or {}

local iA = require'iA'
local mty = require'metaty'
local ds = require'ds'
local info = require'ds.log'.info
local pegl = require'pegl'
local lua = require'pegl.lua'

local isEmpty, notEmpty = pegl.isEmpty, pegl.notEmpty
local EMPTY        = pegl.EMPTY
local PIN, UNPIN   = pegl.PIN, pegl.UNPIN
local Not, Pat, Or = pegl.Not, pegl.Pat, pegl.Or
local Maybe, Many  = pegl.Maybe, pegl.Many


local common = pegl.common
local byte, char = string.byte, string.char
local push = table.insert

M.tableToIa = {}
M.toIa = function(tok)
  assert(tok.kind, 'only supports tokens with a kind')
  local toFn = M.tableToIa[tok.kind]; if not toFn then
    error(tok.kind..' is not a known kind')
  end
  return toFn(tok)
end

M.rvalue = Or{name='rvalue'}
M.lvalue = Or{name='lvalue'}

M.num = Or{
  'true', 'false',
  common.base16, common.base2, common.base10
}

M.literal = Or{M.num, lua.str}

-- form: neg? number (. number)
local extractNum = function(t) --> str
  return (isEmpty(t[1]) and '' or '-1')
       ..t[2]
       ..(isEmpty(t[3]) and '' or ('.'..t[4]))
end
ds.update(M.tableToIa, {
  ['false'] = function() return iA.literal(0) end,
  ['true']  = function() return iA.literal(1) end,
  base2 = function(t)
    return iA.literal(tonumber(t[1], 2))
  end,
  base10 = function(t)
    return iA.literal(tonumber(extractNum(t), 10))
  end,
  base16 = function(t)
    return iA.literal(tonumber(extractNum(t), 16))
  end,
})

--- ( rvalue ): used for i.e. (A = 3) += ...
M.group = {kind='group', '(', M.rvalue, ')'}
M.tableToIa.group = function(t) return toIa(t[2]) end

M.keyword = pegl.Key{name='keyw', {
  'do', 'end', 'if', 'else', 'elseif',
  'loop', 'then', 'until',
  'fn', 'return',
}}

M.reg = {}
for b=byte'A',byte'Z' do push(M.reg, char(b)) end
M.reg = pegl.Key{kind='reg', M.reg}

M.name   = {UNPIN, Not{M.keyword}, common.name}
M.tableToIa.name = function(r) return iA.Var{name=r[1]} end

M.tySpec = {kind='tySpec', ':', common.ty}
M.var    = {kind='var',
  Maybe'$', M.reg, Maybe(M.name),
  Maybe(M.tySpec),
}

M.tableToIa.var = function(r)
  local reg = r[2][1]; assert(iA.Reg.name(reg))
  return iA.Var{
    imm=isEmpty(r[1]) or nil, reg=reg,
    name=notEmpty(r[3]) and r[3][1] or nil,
    ty=notEmpty(r[4]) and assert(r[4][2][1]) or nil,
  }
end

--- An expr1 value
M.val = Or{M.var, M.literal}

--- Operation token lookup.
--- See iA.Op
M.eqOpToken = {
  ['=']   = 'MOV',
  ['~=']  = 'INV',
  ['|=']  = 'BOR', ['&=']  = 'BAND',
  ['+=']  = 'ADD', ['-=']  = 'SUB',
  ['%=']  = 'MOD',
  ['<<='] = 'SHL', ['>>='] = 'SHR',
}

local _eq = {['=']=true} -- tokens end in =
M.eqOp = {
  ['='] = true,
  ['~'] = _eq,
  ['|'] = _eq, ['&'] = _eq,
  ['+'] = _eq, ['-'] = _eq,
  ['%'] = _eq,
  ['<'] = {['<']=_eq}, -- <<=
  ['>'] = {['>']=_eq}, -- >>=
}
M.eqOp = pegl.Key{M.eqOp, kind='eqOp'}

M.eq = {kind='eq', M.lvalue, M.eqOp, M.rvalue}
M.tableToIa.eq = function(tok)
  return iA.Expr1{
    kind=iA.Expr1Kind.EQ1,
    op=iA.Op.name(assert(M.eqOpToken[tok[2][1]])),
    M.toIa(tok[1]), M.toIa(tok[3]),
  }
end

M.fnArgs    = {UNPIN, '(', PIN,
  M.rvalue, Many{',', M.rvalue}, Maybe',',
')'}
--- eXecute a function, using only first return value.
M.fn1    = {UNPIN, M.name, M.fnArgs}
--- eXecute a macro.
M.macrox = {UNPIN, '#', PIN, M.name, Or{M.fnArgs, M.lvalue}}

ds.extend(M.rvalue, {
  M.macrox, M.fnArgs, M.literal,
  M.fn1, M.eq,
  M.reg, M.name,
})

ds.extend(M.lvalue, {
  M.macrox, M.group, M.literal,
  M.reg, M.name,
})

M.stmt = Or{name = 'stmt'} -- (to be extended)
M.block = {kind='block', Many{M.stmt}}

M.cmpOp = pegl.Key{{
  '==', '~=',
  '<',  '<=',
  '>',  '>=',
}}
M.cmp = {M.lvalue, M.cmpOp, PIN, M.lvalue}

M.fnMulti = {M.lvalue, Many{min=1, ',', PIN, M.lvalue}, '=', M.fn1}

M.loc    = Pat{common.nameStr, kind='loc'}
M.setloc = {'::', PIN, M.loc, '::'}
M.goto_  = {'goto', PIN, M.loc}
M.if_ = {
  'if', PIN, M.block,
  Or{
    M.goto_, {
    Many {'elif', PIN, M.block},
    Maybe{'else', PIN, M.block},
    'end',
    }
  },
}

ds.extend(M.stmt, {
  M.loc, M.goto_, M.if_,
  M.fnMulti, M.lvalue,
})


return M

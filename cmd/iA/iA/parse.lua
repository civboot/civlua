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
function M.toIa(self)
  assert(self.kind, 'only supports tokens with a kind')
  local toFn = M.tableToIa[self.kind]; if not toFn then
    error(self.kind..' is not a known kind')
  end
  return toFn(self)
end

M.rvalue = Or{name='rvalue'}
M.lvalue = Or{name='lvalue'}

M.num = Or{
  'true', 'false',
  common.base16, common.base2, common.base10
}

M.literal = Or{M.num, lua.str}

-- form: neg? number (. number)
local function extractNum(t) --> str
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
function M.tableToIa:group() return toIa(self[2]) end

M.keyword = pegl.Key{name='keyw', {
  'do', 'end', 'if', 'else', 'elseif',
  'loop', 'then', 'until',
  'fn', 'return',
}}

M.reg = {}
for b=byte'A',byte'Z' do push(M.reg, char(b)) end
M.reg = pegl.Key{kind='reg', M.reg}

M.name   = {UNPIN, Not{M.keyword}, common.name}
function M.tableToIa:name() return iA.Var{name=self[1]} end

M.tySpec = {kind='tySpec', ':', common.ty}
M.var    = {kind='var',
  Maybe'$', M.reg, Maybe(M.name),
  Maybe(M.tySpec),
}

function M.tableToIa:var()
  local reg = self[2][1]; assert(iA.Reg.name(reg))
  return iA.Var{
    imm=isEmpty(self[1]) or nil, reg=reg,
    name=notEmpty(self[3]) and self[3][1] or nil,
    ty=notEmpty(self[4]) and assert(self[4][2][1]) or nil,
  }
end

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

M.cmpOp = pegl.Key{{
  ['='] = {['=']=true}, ['~'] = {['='] = true}, -- == and ~=
  ['<']={true, ['=']=true},                     -- <  and <=
  ['>']={true, ['=']=true},                     -- >  and >=
}}
M.cmp = {kind='cmp', UNPIN, M.rvalue, M.cmpOp, PIN, M.rvalue}
function M.tableToIa:eq()
  return iA.Cmp{l=M.toIa(self[1]), op=self[2][1], r=M.toIa(self[3])}
end

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

M.eq = {kind='eq',
  UNPIN, M.lvalue, Not{M.cmpOp},
  M.eqOp, PIN, M.rvalue
}
function M.tableToIa:eq()
  return iA.Expr1{
    kind=iA.Expr1Kind.EQ1,
    op=iA.Op.name(assert(M.eqOpToken[self[2][1]])),
    M.toIa(self[1]), M.toIa(self[3]),
  }
end

M.fnArgs    = {UNPIN, '(', PIN,
  M.rvalue, Many{',', M.rvalue}, Maybe',',
')'}
--- eXecute a function
M.fncall    = {UNPIN, M.name, M.fnArgs}
--- eXecute a macro.
M.macrox = {UNPIN, '#', PIN, M.name, Or{M.fnArgs, M.lvalue}}

ds.extend(M.rvalue, {
  M.macrox, M.fnArgs, M.literal,
  M.fncall, M.eq,
  M.reg, M.name,
})

ds.extend(M.lvalue, {
  M.macrox, M.group, M.literal,
  M.reg, M.name,
})

M.stmt = Or{name = 'stmt'} -- (to be extended)
M.block = {kind='block', Many{M.stmt}}
M.tableToIa['block'] = function(t)
  local b = {}
  for i, stmt in ipairs(t) do b[i] = M.toIa(stmt) end
  return b
end

M.assign = {kind='assign',
  UNPIN, M.lvalue, Not{M.cmpOp}, Many{',', M.lvalue},
  '=', PIN, M.rvalue,
}
M.tableToIa['assign'] = function(t)
  local a = iA.Assign{eq=M.toIa(t[#t])}
  a[1] = M.toIa(t[1])
  for i=2,#t-2 do a[i] = M.toIa(t[i][2]) end
  return a
end

M.goto_  = {kind='goto', UNPIN, 'goto', PIN, M.name}
M.tableToIa['goto'] = function(t)
  return iA.Goto{to=assert(t[2][1])}
end

M.if_ = {kind='if',
  UNPIN,       'if',   PIN, M.block, 'do', M.block,
  Many {UNPIN, 'elif', PIN, M.block, 'do', M.block},
  Maybe{UNPIN, 'else', PIN, M.block},
  'end',
}

local function condBlockToIa(t)
  local cond = iA.CondBlock{cond=M.toIa(t[2])}
  for i, stmt in ipairs(t[4]) do cond[i] = M.toIa(stmt) end
  return cond
end
M.tableToIa['if'] = function(t)
  local if_ = iA.If{condBlockToIa(t)}
  for i=5,#t-2 do push(if_, condBlockToIa(t[i])) end
  local elseTok = t[#t-1]
  if notEmpty(elseTok) then if_.else_ = M.toIa(elseTok) end
  return if_
end

ds.extend(M.stmt, {
  M.goto_, M.if_,
  M.cmp, M.assign, M.eq,
  M.lvalue,
})

return M

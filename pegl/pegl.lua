-- rd: recursive descent parser

local mty     = require'metaty'
local ds      = require'ds'
local civtest = require'civtest'
local ty = mty.ty
local extend, lines = ds.extend, ds.lines
local add, sfmt = table.insert, string.format

local M = {}

M.Token = mty.record'Token'
  :field('l', 'number')  :field('c', 'number')
  :field('l2', 'number') :field('c2', 'number')
  :fieldMaybe'kind'

M.Token.__fmt = function(t, f)
  if t.kind then extend(f, {'Token(', t.kind, ')'})
  else mty.tblFmt(t, f) end
end

M.RootSpec = mty.record'RootSpec'
  -- function(p): skip empty space
  -- default: skip whitespace
  :field('skipEmpty', 'function')
  -- skipComment: return Token for found comment.
  :fieldMaybe('skipComment', 'function')
  :field('tokenizer', 'function')
  :field('dbg', 'boolean', false)
  :field('fmtKind', 'table') -- default set at bottom

M.Parser = mty.record'Parser'
  :field'dat'
  :field'l' :field'c' :fieldMaybe'line' :field'lines'
  :field('root', M.RootSpec)
  :field('stack', 'table')
  :fieldMaybe'stackLast'
  :field('commentLC', 'table')
  :field('dbgLevel', 'number', 0)

M.fmtSpec = function(s, f)
  if type(s) == 'string' then
    return add(f, string.format("%q", s))
  end
  if type(s) == 'function' then
    return add(f, mty.fmt(s))
  end
  if s.name or s.kind then
    add(f, '<'); add(f, s.name or s.kind); add(f, '>')
    return
  end
  if mty.ty(s) ~= 'table' then add(f, mty.tyName(mty.ty(s))) end
  f:levelEnter('{')
  for i, sub in ipairs(s) do
    M.fmtSpec(sub, f);
    if i < #s then f:sep(' ') end
  end
  f:levelLeave('}')
end
M.specToStr = function(s, set)
  local set = set or mty.FmtSpec{}
  if set.pretty == nil then set.pretty = true end
  local f = mty.Fmt{set=set}; M.fmtSpec(s, f)
  return f:toStr()
end

local function newSpec(name, fields)
  local r = mty.record(name)
  r.__index = mty.indexUnchecked
  r.__fmt = M.fmtSpec
  for _, args in ipairs(fields or {}) do
    local n, t = table.unpack(args)
    r:fieldMaybe(n, t)
  end
  return r
end

local FIELDS = {
  {'kind', 'string'},
  {'name', 'string'}, -- for fmt only
}
M.Pat = mty.doc[[Pat'pat%wern' or Pat{'pat', kind='foo'}]]
(ds.imm(newSpec('Pat'))
  :fieldMaybe'kind' :fieldMaybe'name')
M.Pat:new(function(ty_, t)
  if type(t) == 'string' then t = {t} end
  assert(#t > 0, 'must specify a pattern')
  return ds.newImm(ty_, t)
end)

local KEY_FORM =
  "construct Keys like Keys{{'kw1', 'kw2', kw3=true, kw4={sub-keys}, kind=...}"

local function constructKeys(keys)
  assert(mty.ty(keys) == 'table', KEY_FORM)
  for i=1,#keys do
    keys[keys[i]] = true;
    keys[i] = nil end
  for k, v in pairs(keys) do
    if k == true then assert(v == true)
    else mty.assertf(
      type(k) == 'string', 'number key after list items: %s', k)
    end
    if mty.ty(v) == 'table' then keys[k] = constructKeys(v)
    else mty.assertf(v == true, '%s: %s', KEY_FORM, mty.fmt(v)) end
  end
  return keys
end

M.Key = newSpec'Key' -- Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}
  :field'keys' :fieldMaybe'name' :fieldMaybe'kind'
M.Key:new(function(ty_, k)
  local keys = assert(table.remove(k, 1), 'must provide keys at index 1')
  k['keys'] = constructKeys(keys)
  return mty.newUnchecked(ty_, k)
end)

M.Or = newSpec('Or', FIELDS)
M.Maybe = function(spec) return M.Or{spec, M.Empty} end
M.Many = newSpec'Many'
  :fieldMaybe('kind', 'string')
  :field('min', 'number', 0)
  :fieldMaybe('name', 'string')
M.Seq = newSpec('Seq', FIELDS)
M.Not = newSpec('Not', FIELDS)

-- Used in Seq to "pin" or "unpin" the parser, affecting when errors
-- are thrown.
M.PIN   = ds.newSentinel('PIN',   {name='PIN'})
M.UNPIN = ds.newSentinel('UNPIN', {name='UNPIN'})

-- Denotes a missing node. When used in a spec simply returns Empty.
-- Example: Or{Integer, String, Empty}
M.EmptyTy = ds.imm(newSpec('Empty', FIELDS))
M.Empty = M.EmptyTy{kind='Empty'}
M.EMPTY = ds.Imm{kind='Empty'}
assert(M.EMPTY.kind == 'Empty')

-- Denotes the end of the file
M.EofTy = ds.imm(newSpec('EOF', FIELDS))
M.Eof = M.EofTy{kind='EOF'}
M.EOF = ds.Imm{kind='EOF'}

-------------------
-- Root and Utilities

M.skipWs1 = function(p)
  if p.c > #p.line then p:incLine(); return
  else
    local c, c2 = p.line:find('^%s+', p.c)
    if c then p.c = c2 + 1; return end
  end
  return true
end

-- Default skipEmpty function.
M.RootSpec.skipEmpty = function(p)
  local loop, sc, cmt, cL = true, p.root.skipComment
  while loop and not p:isEof() do
    loop = not M.skipWs1(p)
    if sc then
      cL = p.commentLC[p.l]; cmt = (cL and cL[p.c]) or sc(p)
      if cmt then -- cache for later and advance
        p:dbg('COMMENT: %s.%s', p.l, c)
        cL = p.commentLC[p.l]
        if not cL then cL = {}; p.commentLC[p.l] = cL end
        cL[p.c] = cmt
        p.l, p.c = cmt.l2, cmt.c2 + 1
      end
    end
  end
end

M.defaultTokenizer = function(p)
  if p:isEof() then return end
  return p.line:match('^%p', p.c) or p.line:match('^[_%w]+', p.c)
end
M.RootSpec.tokenizer = M.defaultTokenizer

-- TODO: the civ version had M.Tbl which was (accidentally) null.
-- Do we want 'table' here?
local UNPACK_SPECS = ds.Set{M.Seq, M.Many, M.Or, --[['table']]}
local function shouldUnpack(spec, t)
  local r = (
    type(t) == 'table'
    and UNPACK_SPECS[ty(spec)]
    and ty(t) ~= M.Token
    and not spec.kind
    and not t.kind
  )
  return r
end

-- Create node with optional kind
local function node(spec, t, kind)
  if type(t) ~= 'boolean' and t and kind then
    if type(t) == 'table' and not t.kind then
      t.kind = kind
    else t = {t, kind=kind} end
  end
  if t and shouldUnpack(spec, t) and #t == 1 then
    t = t[1]
  end
  return t
end

-------------------
-- Key

M.Key.parse = function(key, p)
  p:skipEmpty();
  local c, keys, found = p.c, key.keys, false
  while true do
    local k = p.root.tokenizer(p); if not k    then break end
    keys = keys[k];                if not keys then break end
    p.c = p.c + #k
    if keys == true then found = true; break end
    found = keys[true]
  end
  if found then
    local kind = key.kind or lines.sub(p.dat, p.l, c, p.l, p.c - 1)
    return M.Token{kind=kind, l=p.l, c=c, l2=p.l, c2=p.c - 1}
  end
  p.c = c
end

-------------------
-- Pat
M.Pat.parse = function(self, p)
  p:skipEmpty()
  for _, pat in ipairs(self) do
    local t = p:consume(pat)
    if t then
      t.kind = self.kind
      p:dbgMatched(t.kind or pat)
      return t
    end
  end
end

-------------------
-- Seq

local function _seqAdd(p, out, spec, t)
  if type(t) == 'boolean' then -- skip
  elseif shouldUnpack(spec, t) then
    p:dbgUnpack(spec, t)
    extend(out, t)
  else add(out, t) end
end

local function parseSeq(p, seq)
  p:skipEmpty()
  local out, pin = {}, nil
  p:dbgEnter(seq)
  for i, spec in ipairs(seq) do
    if     spec == M.PIN   then pin = true;  goto continue
    elseif spec == M.UNPIN then pin = false; goto continue
    end
    local t = p:parse(spec)
    if not t then
      p:dbgMissed(spec)
      p:dbgLeave()
      return p:checkPin(pin, spec)
    end
    _seqAdd(p, out, spec, t)
    pin = (pin == nil) and true or pin
    ::continue::
  end
  local out = node(seq, out, seq.kind)
  p:dbgLeave(out)
  return out
end

M.Seq.parse = function(seq, p) return parseSeq(p, seq) end

-------------------
-- Or
M.Or.parse = function(or_, p)
  p:skipEmpty()
  p:dbgEnter(or_)
  local state = p:state()
  for _, spec in ipairs(or_) do
    local t = p:parse(spec)
    if t then
      t = node(spec, t, or_.kind)
      p:dbgLeave(t)
      return t
    end
    p:setState(state)
  end
  p:dbgLeave()
end

-------------------
-- Or
M.Many.parse = function(many, p)
  p:skipEmpty()
  local out = {}
  p:dbgEnter(many)
  while true do
    local t = parseSeq(p, many)
    if not t then break end
    if ty(t) ~= M.Token and #t == 1 then add(out, t[1])
    else _seqAdd(p, out, many, t) end
  end
  if #out < many.min then
    p:dbgMissed(many, ' got count=%s', #out)
    out = nil
  end
  p:dbgLeave(many)
  return node(many, out, many.kind)
end

-------------------
-- Misc
M.Not.parse = function(self, p) return not parseSeq(p, self) end
M.EofTy.parse = function(self, p)
  p:skipEmpty(); if p:isEof() then return M.EOF end
end
M.EmptyTy.parse = function() return M.EMPTY end

local SPEC_TY = {
  ['function']=function(p, fn) p:skipEmpty() return fn(p) end,
  string=function(p, kw)
    p:skipEmpty();
    local tk = p.root.tokenizer(p)
    if kw == tk then
      local c = p.c; p.c = c + #kw
      return M.Token{kind=kw, l=p.l, c=c, l2=p.l, c2=p.c - 1}
    end
  end,
  table=function(p, tbl) return parseSeq(p, M.Seq(tbl)) end,
}

-- parse('hi + there', {Pat{'\w+'}, '+', Pat{'\w+'}})
-- Returns tokens: 'hi', {'+', kind='+'}, 'there'
M.parse = function(dat, spec, root)
  local p = M.Parser.new(dat, root)
  return p:parse(spec)
end

local function toStrTokens(dat, n)
  if not n then return nil end
  if n == M.EofTy   then return n end
  if n == M.EmptyTy then return n end
  if ty(n) == M.Token then
    return node(Pat, lines.sub(dat, n.l, n.c, n.l2, n.c2), n.kind)
  end
  local out = {kind=n.kind}
  for _, n in ipairs(n) do
    add(out, toStrTokens(dat, n))
  end
  return out
end; M.toStrTokens = toStrTokens

local function defaultDat(dat)
  if type(dat) == 'string' then return lines.split(dat)
  else return dat end
end

-- Parse and convert into StrTokens. Str tokens are
-- tables (lists) with the 'kind' key set.
--
-- This is primarily used for testing
M.parseStrs=function(dat, spec, root)
  local dat = defaultDat(dat)
  local node = M.parse(dat, spec, root)
  return toStrTokens(dat, node)
end

M.parsedFmt = function(t, f)
  local fmtK = f.set.data and f.set.data.fmtKind
  local fmtK = t.kind and fmtK and fmtK[t.kind]
  if #t == 1 and t.kind == t[1] then add(f, sfmt('KW%q', t[1]))
  elseif fmtK then fmtK(t, f)
  else mty.tblFmt(t, f) end
end

M.assertParse=function(t) -- {dat, spec, expect, dbg=false, root=RootSpec{}}
  assert(t.dat, 'dat'); assert(t.spec, 'spec')
  local root = t.root or M.RootSpec{}
  root.dbg   = t.dbg or root.dbg
  local result = M.parseStrs(t.dat, t.spec, root)
  if not t.expect and t.parseOnly then return end
  if t.expect ~= result then
    local set = mty.FmtSet{
      pretty=true,  tblFmt=M.parsedFmt,
      listSep=', ', tblSep=', ',
      data=t.root,
    }
    local eStr = mty.fmt(t.expect, set)
    local rStr = mty.fmt(result, set)
    if eStr ~= rStr then
      print('\n#### EXPECT:'); print(eStr)
      print('\n#### RESULT:'); print(rStr)
      print()
      local b = {}; civtest.diffFmt(b, eStr, rStr)
      print(table.concat(b))
      assert(false, 'failed parse test')
    end
  end
end

M.assertParseError=function(t)
  civtest.assertErrorPat(
    t.errPat,
    function() M.parse(assert(t.dat), assert(t.spec)) end,
    t.plain)
end

M.Parser.__tostring=function() return 'Parser()' end
M.Parser.new = function(dat, root)
  dat = defaultDat(dat)
  return M.Parser{
    dat=dat, l=1, c=1, line=dat[1], lines=#dat,
    root=root or M.RootSpec{},
    stack={},
    commentLC={},
  }
end
M.Parser.parse = function(p, spec)
  local ty_ = mty.ty(spec)
  local specFn = SPEC_TY[ty_]
  if specFn then return specFn(p, spec)
  else           return spec:parse(p)
  end
end
M.Parser.peek = function(p, pat)
  if p:isEof() then return nil end
  local c, c2 = p.line:find(pat, p.c)
  if c == p.c then return M.Token{l=p.l, c=c, l2=p.l, c2=c2} end
end
M.Parser.consume = function(p, pat, plain)
  local t = p:peek(pat, plain)
  if t then p.c = t.c2 + 1 end
  return t
end
M.Parser.sub =function(p, t) -- t=token
  return lines.sub(p.dat, t.l, t.c, t.l2, t.c2)
end
M.Parser.incLine=function(p)
  p.l, p.c = p.l + 1, 1
  p.line = p.dat[p.l]
end
M.Parser.isEof=function(p) return not p.line end
M.Parser.skipEmpty=function(p)
  p.root.skipEmpty(p)
  return p:isEof()
end
M.Parser.state   =function(p) return {l=p.l, c=p.c, line=p.line} end
M.Parser.setState=function(p, st) p.l, p.c, p.line = st.l, st.c, st.line end

local function fmtStack(p)
  local stk = p.stack
  local b = {}; for _, v in ipairs(stk) do
    if v == true then -- skip
    elseif type(v) == 'string' then add(b, v)
    else add(b, mty.fmt(v)) end
  end
  add(b, sfmt('%s', p.stackLast))
  return table.concat(b, ' -> ')
end
M.Parser.checkPin=function(p, pin, expect)
  if not pin then return end
  local stk = fmtStack(p)
  if p.line then
    mty.errorf(
      "ERROR %s.%s\nstack: %s\nparser expected: %s\nGot: %s",
      p.l, p.c, stk, expect, p.line:sub(p.c))
  else
    mty.errorf(
      "ERROR %s.%s\nstack: %s\nparser reached EOF but expected: %s",
      p.l, p.c, stk, expect)
  end
end

M.Parser.dbgEnter=function(p, spec)
  add(p.stack, spec.kind or spec.name or true)
  if not p.root.dbg then return end
  p:dbg('ENTER: %s', mty.fmt(spec))
  p.dbgLevel = p.dbgLevel + 1
end
M.Parser.dbgLeave=function(p, n)
  local sn = table.remove(p.stack); p.stackLast = sn
  if not p.root.dbg then return n end
  p.dbgLevel = p.dbgLevel - 1
  p:dbg('LEAVE: %s', mty.fmt(n or sn))
  return n
end
M.Parser.dbgMatched=function(p, spec)
  if not p.root.dbg then return end
  p:dbg('MATCH: %s', mty.fmt(spec))
end
M.Parser.dbgMissed=function(p, spec, note)
  if not p.root.dbg then return end
  p:dbg('MISS: %s%s', mty.fmt(spec), (note or ''))
end
M.Parser.dbgUnpack=function(p, spec, t)
  if not p.root.dbg then return end
  p:dbg('UNPACK: %s :: %s', mty.fmt(spec), mty.fmt(t))
end
M.Parser.dbg=function(p, fmt, ...)
  if not p.root.dbg then return end
  local msg = sfmt(fmt, ...)
  mty.pnt(string.format('%%%s%s (%s.%s)',
    string.rep('* ', p.dbgLevel), msg, p.l, p.c))
end


local _dec, _hpat = M.Pat'[0-9]+', '[a-fA-F0-9]+'
local dec = {kind='dec',
  M.UNPIN, M.Maybe'-',  _dec, M.Maybe{'.', _dec}
}
local hex = {kind='hex',
  M.UNPIN, M.Maybe'-',  M.Pat('0x'.._hpat),
  M.Maybe{'.', M.Pat(_hpat)},
}
local num = M.Or{name='num', hex, dec}
M.common = {num=num, dec=dec, hex=hex}

-- Debugging keywords(KW), names(N) and numbers(DEC/HEX)
M.testing = {}
function M.testing.KW(kw)  return {kw, kind=kw} end       -- keyword
function M.testing.N(name) return {name, kind='name'} end -- name
local function NUM(kind, t)
  if type(t) == 'string' then t = {t} end; assert(#t == 1)
  return {kind=kind, t.neg and '-' or M.EMPTY, t[1], t.deci or M.EMPTY}
end
function M.testing.DEC(t) return NUM('dec', t) end
function M.testing.HEX(t) return NUM('hex', t) end

-- formatting parsed so it can be copy/pasted
local fmtKindNum = function(name, t, f) add(f, name..sfmt(
  '{%s%s%s}', mty.eq(t[1],M.EMPTY) and '' or 'neg=true ',
  t[2], mty.eq(t[3],M.EMPTY) and '' or 'point='..t[3][2]
))end
M.RootSpec.fmtKind = {
  name  = function(t, f) add(f, sfmt('N%q', t[1])) end,
  EOF   = function(t, f) add(f, 'EOF')   end,
  EMPTY = function(t, f) add(f, 'EMPTY') end,
  dec   = function(t, f) fmtKindNum('DEC', t, f) end,
  hex   = function(t, f) fmtKindNum('HEX', t, f) end,
}

return M

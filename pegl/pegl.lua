-- rd: recursive descent parser

local mty     = require'metaty'
local ds      = require'ds'
local civtest = require'civtest'
local ty = mty.ty
local extend, lines = ds.extend, ds.lines
local add, sfmt = table.insert, string.format

local M = {}
local SPEC = {}

M.Token = mty.record'Token'
  :field'kind'
  :field('l', 'number')  :field('c', 'number')
  :field('l2', 'number') :field('c2', 'number')

M.Token.__fmt = function(t, f)
  if t.kind then extend(f, {'Token(', t.kind, ')'})
  else mty.tblFmt(t, f) end
end

M.RootSpec = mty.record'RootSpec'
  -- function(p): skip empty space
  -- default: skip whitespace
  :field('skipEmpty', 'function')
  :field('tokenizer', 'function')
  :field('dbg', 'boolean', false)
  :field'punc1' :field'punc2'

M.Parser = mty.record'Parser'
  :field'dat'
  :field'l' :field'c' :field'line' :field'lines'
  :field('root', M.RootSpec)
  :field('dbgIndent', 'number', 0)

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
  add(f, mty.tyName(s));
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
  for _, args in ipairs(fields or {}) do r:field(table.unpack(args)) end
  return r
end

local FIELDS = {
  {'kind', 'string', false},
  {'name', 'string', false}, -- for fmt only
}
M.Pat = newSpec('Pat')
  :fieldMaybe'pattern' :fieldMaybe'kind' :fieldMaybe'name'
M.Pat:new(function(ty_, pattern, kind)
  return setmetatable({pattern=pattern, kind=kind}, M.Pat)
end)

M.Key = newSpec'Key'
  :fieldMaybe'keys' :fieldMaybe'name' :fieldMaybe'kind'
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
M.PIN   = {name='PIN'}
M.UNPIN = {name='UNPIN'}

-- Denotes a missing node. When used in a spec simply returns Empty.
-- Example: Or{Integer, String, Empty}
M.EmptyTy = newSpec('Empty', FIELDS)
M.Empty = M.EmptyTy{kind='Empty'}
M.EmptyNode = {kind='Empty'}

-- Denotes the end of the file
M.EofTy = newSpec('EOF', FIELDS)
M.EOF = M.EofTy{kind='EOF'}
M.EofNode = {kind='EOF'}

-- Default skipEmpty function.
M.RootSpec.skipEmpty = function(p)
  while true do
    if p:isEof() then return end
    if p.c > #p.line then p:incLine()
    else
      local c, c2 = string.find(p.line, '^%s', p.c)
      if not c then return end
      p.c = c2 + 1
    end
  end
end

local function tokenizePunc(p, punc, pat)
  if not punc then return end
  local m = p.line:match(pat, p.c)
  if punc[m] then return m end
end; M.tokenizePunc = tokenizePunc

M.defaultTokenizer = function(p)
  p:skipEmpty(); if p:isEof() then return end
  return (
    tokenizePunc(p, p.root.punc2, '^%p%p')
    or tokenizePunc(p, p.root.punc1, '^%p')
    or p.line:match('^%w+', p.c)
  )
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
    and not rawget(spec, 'kind')
    and not rawget(t,    'kind')
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

local function patImpl(p, kind, pattern, plain)
  local t = p:consume(pattern, plain)
  if t then
    p:dbgMatched(kind or pattern)
    t.kind = kind
  end
  return t
end

local function _seqAdd(p, out, spec, t)
  if type(t) == 'boolean' then -- skip
  elseif shouldUnpack(spec, t) then
    p:dbgUnpack(spec, t)
    extend(out, t)
  else add(out, t) end
end

local function parseSeq(p, seq)
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

local function parseOr(p, or_)
  p:skipEmpty()
  p:dbgEnter(or_)
  local state = p:state()
  for _, spec in ipairs(or_) do
    local t = p:parse(spec)
    if t then
      t = node(spec, t, or_.kind); p:dbgLeave(t)
      return t
    end
    p:setState(state)
  end
  p:dbgLeave()
end


local function keyImpl(p, keys, kind)
  p:skipEmpty();
  local l, c = p.l, p.c
  local k = p.root.tokenizer(p)
  if k and keys[k] then
    p.c = c + #k
    return M.Token{kind=kind or k, l=l, c=c, l2=l, c2=p.c - 1}
  end
end

ds.update(SPEC, {
  ['string']=function(p, keyword) return keyImpl(p, {[keyword]=true}) end,
  [M.Key]=function(p, key) return keyImpl(p, key.keys, key.kind) end,
  [M.Pat]=function(p, pat) return patImpl(p, pat.kind, pat.pattern, false) end,
  [M.EmptyTy]=function() return M.EmptyNode end,
  [M.EofTy]=function(p)
    p:skipEmpty(); if p:isEof() then return M.EofNode end
  end,
  ['function']=function(p, fn) p:skipEmpty() return fn(p) end,
  [M.Or]=parseOr,
  [M.Not]=function(p, spec) return not parseSeq(p, spec) end,
  [M.Seq]=parseSeq,
  ['table']=function(p, seq) return parseSeq(p, M.Seq(seq)) end,
  [M.Many]=function(p, many)
    local out = {}
    local seq = ds.copy(many); seq.kind = nil
    p:dbgEnter(many)
    while true do
      local t = parseSeq(p, seq)
      if not t then break end
      if ty(t) ~= M.Token and #t == 1 then add(out, t[1])
      else _seqAdd(p, out, many, t) end
    end
    if #out < many.min then
      out = nil
      p:dbgMissed(many, ' got count='..#out)
    end
    p:dbgLeave(many)
    return node(many, out, many.kind)
  end,
})

-- parse('hi + there', {Pat('\w+'), '+', Pat('\w+')})
-- Returns tokens: 'hi', {'+', kind='+'}, 'there'
M.parse=function(dat, spec, root)
  local p = M.Parser.new(dat, root)
  return p:parse(spec)
end

local function toStrTokens(dat, n)
  if not n then return nil end
  if SPEC[n] then
    return n
  end
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

M.assertParse=function(t) -- {dat, spec, expect, dbg=false, root=RootSpec{}}
  assert(t.dat, 'dat'); assert(t.spec, 'spec')
  local root = t.root or RootSpec{}
  root.dbg   = t.dbg or root.dbg
  local result = M.parseStrs(t.dat, t.spec, root)
  if t.expect ~= result then
    civtest.assertEq(
      mty.fmt(t.expect, mty.FmtSet{pretty=true}),
      mty.fmt(result,   mty.FmtSet{pretty=true}))
  end
end

M.assertParseError=function(t)
  civtest.assertErrorPat(
    t.errPat,
    function() M.parse(assert(t.dat), assert(t.spec)) end,
    t.plain)
end

M.Parser.__tostring=function() return 'Parser()' end
M.Parser.new=function(dat, root)
  dat = defaultDat(dat)
  return M.Parser{
    dat=dat, l=1, c=1, line=dat[1], lines=#dat,
    root=root or RootSpec{},
  }
end
M.Parser.parse=function(p, spec)
  local specFn = SPEC[ty(spec)]
  return specFn(p, spec)
end
M.Parser.peek=function(p, pattern, plain)
  if p:skipEmpty() then return nil end
  local c, c2 = nil, nil
  if not plain or not pattern:find('%w+') then
    -- not plain or only symbols in pattern
    c, c2 = p.line:find(pattern, p.c, plain)
  else -- plain word-like, tokenize
    if pattern == p.line:match('^'..pattern..'%w*', p.c) then
      c, c2 = p.c, p.c + #pattern - 1
    end
  end
  if c == p.c then return M.Token{l=p.l, c=c, l2=p.l, c2=c2} end
end
M.Parser.consume=function(p, pattern, plain)
  local t = p:peek(pattern, plain)
  if t then p.c = t.c2 + 1 end
  return t
end
M.Parser.sub=function(p, t) -- t=token
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

M.Parser.parse=function(p, spec)
  return SPEC[ty(spec)](p, spec)
end
M.Parser.checkPin=function(p, pin, expect)
  if not pin then return end
  if p.line then
    mty.errorf(
      "ERROR %s.%s, parser expected: %s\nGot: %s",
      p.l, p.c, expect, p.line:sub(p.c))
  else
    mty.errorf(
      "ERROR %s.%s, parser reached EOF but expected: %s",
      p.l, p.c, expect)
  end
end

M.Parser.dbgEnter=function(p, spec)
  if not p.root.dbg then return end
  p:dbg('ENTER:%s', mty.fmt(spec))
  p.dbgIndent = p.dbgIndent + 1
end
M.Parser.dbgLeave=function(p, n)
  if not p.root.dbg then return end
  p.dbgIndent = p.dbgIndent - 1
  p:dbg('LEAVE: %s', mty.fmt(n or '((none))'))
end
M.Parser.dbgMatched=function(p, spec)
  if not p.root.dbg then return end
  p:dbg('MATCH:%s', mty.fmt(spec))
end
M.Parser.dbgMissed=function(p, spec, note)
  if not p.root.dbg then return end
  p:dbg('MISS:%s%s', mty.fmt(spec), (note or ''))
end
M.Parser.dbgUnpack=function(p, spec, t)
  if not p.root.dbg then return end
  p:dbg('UNPACK: %s :: %s', fmt(spec), fmt(t))
end
M.Parser.dbg=function(p, fmt, ...)
  if not p.root.dbg then return end
  local msg = sfmt(fmt, ...)
  mty.pnt(string.format('%%%s %s (%s.%s)',
    string.rep('  ', p.dbgIndent), msg, p.l, p.c))
end

return M

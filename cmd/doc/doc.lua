#!/usr/bin/env -S lua
local mty = require'metaty'

--- Builds on metaty to add the ability to extract and format documentation.
---
--- Also offers the Cmd and Cmds types for documenting shell commands.
local M = mty.mod'doc'

local G = mty.G; G.MAIN = G.MAIN or M
local shim = require'shim'
local ds = require'ds'
local fmt = require'fmt'
local pod = require'pod'
local info = require'ds.log'.info
local warn = require'ds.log'.warn
local cxt = require'cxt'

local sfmt, srep = string.format, string.rep
local push = ds.push
local assertf = fmt.assertf

local EMPTY = {}

--- Find the object/name or return nil.
function M.tryfind(obj) --> any?
  if type(obj) ~= 'string' then return obj end
  return G.PKG_LOOKUP[obj] or ds.wantpath(obj)
end

--- Find the object/name.
function M.find(obj) --> any
  return assertf(M.tryfind(obj), '%q could not be found', obj)
end

--- Given a list of comment lines strip the '---' from them.
local function stripComments(c)
  if #c == 0 then return c end
  local ind = c[1]:match'^%-%-%-(%s+)' or ''
  local pat = '^%-%-%-'..string.rep('%s?', #ind)..'(.*)%s*'
  for i, ln in ipairs(c) do c[i] = ln:match(pat) or ln end
  return c
end

--- Object passed to __doc methods.
--- Aids in writing cxt.
M.Doc = mty'Doc' {
  'to [file]: file to write to.',
  'indent [string]', indent = '  ',
  '_hdr      [int]', _hdr   = 1,
  '_level    [int]', _level = 0,
  '_nl [string]',    _nl    = '\n',
}

M.Doc.level  = fmt.Fmt.level
M.Doc._write = fmt.Fmt._write
M.Doc.write  = fmt.Fmt.write
M.Doc.flush  = fmt.Fmt.flush
M.Doc.close  = fmt.Fmt.close

function M.Doc:bold(text) self:write(sfmt('[*%s]', text)) end
function M.Doc:code(code) self:write(cxt.code(code))      end

function M.Doc:link(link, text)
  if text then self:write(sfmt('[<%s>%s]', link, text))
  else         self:write(sfmt('[<%s>]', link)) end
end

function M.Doc:hdrlevel(add) --> int
  if add then
    self._hdr = self._hdr + add
    assert(self._hdr > 0, 'hdr must be > 0')
  end
  return self._hdr
end

function M.Doc:named(name, id)
  self:write(sfmt('[{name=%s}%s]', id or name, assert(name)))
end

function M.Doc:header(content, name)
  if name then
    self:write(sfmt('[{h%s name=%s}%s]\n', self._hdr, name, content))
  else
    self:write(sfmt('[{h%s}%s]\n', self._hdr, content))
  end
end

function M.Doc:anyExtract(obj) --> name, loc, cmt, code
  local name, loc = mty.anyinfo(obj)
  info('@@ anyExtract name=%q loc=%q', name, loc)
  return name, loc, self:extractCode(loc)
end

function M.Doc:extractCode(loc) --> (commentLines, codeLines)
  if not loc then return end
  if type(loc) ~= 'string' then loc = select(2, mty.anyinfo(loc)) end
  if not loc or loc:find'%[' then return end
  local path, locLine = loc:match'(.*):(%d+)'
  if not path then error('loc path invalid: '..loc) end
  local l, lines, locLine = 1, ds.Deq{}, tonumber(locLine)
  local l, lines = 1, ds.Deq{}
  for line in io.lines(path) do -- starting line with 256 lines above.
    lines:push(line); if #lines > 256 then lines:pop() end
    if l == locLine then break end
    l = l + 1
  end
  assert(l == locLine, 'file not long enough')
  -- move the lines to a normal (non Deq) table and put in reverse order.
  lines = ds.reverse(table.move(lines, lines.left, lines.right, 1, {}))
  -- find where the code ends, then get all '---' comments.
  local code, cmts = {}, {}
  for l, line in ipairs(lines) do
    if line:find'^function' or line:find'^%w[^-=]+=' then
      table.move(lines, 1, l, 1, code); break
    end
  end
  for l=#code+1, #lines+1 do local
    line = lines[l]
    -- FIXME: handle leading whitespace
    if not line or not line:find'^%-%-%-' then
      table.move(lines, #code+1, l-1, 1, cmts); break
    end
  end
  cmts = stripComments(ds.reverse(cmts))
  while #cmts > 0 and not cmts[#cmts]:match'%S' do
    cmts[#cmts] = nil
  end
  return cmts, ds.reverse(code)
end

--- Extract the function signature from the lines of code.
function M.Doc:fnsig(code) --> (string, isMethod)
  if not code or not code[1] then return end
  code = code[1]
  local         s, r = code:match'(%b()).*%-%->%s*(.*)'
  if not s then s, r = code:match'(%b{}).*%-%->%s*(.*)' end
  if not s then
    s, r = code:match'function(%b()).*return%s*(.-)%s*end'
  end
  if not s then s    = code:match'function.*(%b())' end
  if not s then return end
  local sig = (s or '(...)')..(r and sfmt(' -> %s', r) or '')
  return sig, code:match'function[^(]+:' and true
end

--- Declare the function definition
function M.Doc:declfn(fn, name, id) --> (cmt, sig, isMethod)
  local pname, loc  = mty.anyinfo(fn)
  local cmt, code   = self:extractCode(loc)
  local sig, isMeth = self:fnsig(code)
  name = (isMeth and 'fn:' or 'fn ')..(name or pname)
  if id then self:write(sfmt('[{*name=%s}%s]', id, name))
  else       self:bold(name) end
  if sig and sig ~= '' then self:code(sig) end
  if cmt and #cmt > 0 then
    self:write'[{br}]\n'
    for i, c in ipairs(cmt) do
      self:write(c); if i < #cmt then self:write'\n' end
    end
  end
  return cmt, sig, isMeth
end

--- Document the module.
function M.Doc:mod(m)
  local name, loc = mty.anyinfo(m)
  local cmts, code = self:extractCode(loc)
  self:header('Mod '..m.__name, m.__name)
  self:hdrlevel(1)
  for _, c in ipairs(cmts or EMPTY) do
    self:write(c); self:write'\n'
  end
  return self:endmod(m, name)
end

--- Document the end (not header+comments) of module.
function M.Doc:endmod(m)
  local names = {}
  local fns, tys, oth = {}, {}, {}
  for _, k in ipairs(m.__attrs) do
    if k:match'^_' then goto continue end
    local v = rawget(m, k);
    if v == nil then
      warn('%s.%s is in __attrs but no longer exists', m.__name, k)
      goto continue
    end
    names[v] = k
    if     type(v) == 'function'                     then push(fns, v)
    elseif type(v) == 'table' and rawget(v, '__doc') then push(tys, v)
    else push(oth, v) end
    ::continue::
  end

  if #tys > 0 then
    self:write'\n'; self:bold'Types: ';
    for _, ty in ipairs(tys) do
      self:level(1)
      self:link(sfmt('#%s.%s', m.__name, names[ty]), names[ty])
      self:level(-1); self:write' '
    end
    self:write'\n\n'
  end

  if #fns > 0 then
    self:bold'Functions'; self:write' [+\n'; 
    for _, fn in ipairs(fns) do
      self:write'* '; self:level(1)
      self:declfn(fn, names[fn], sfmt('%s.%s', m.__name, names[fn]))
      self:level(-1); self:write'\n'
    end
    self:write']\n'
  end

  for _, ty in ipairs(tys) do
    self:write'\n'; rawget(ty, '__doc')(ty, self)
  end
  self:hdrlevel(-1)
end

function M.Doc:__call(name, obj, cmts)
  local ty = type(obj)
  if ty == 'function' then return self:declfn(obj) end
  if ty == 'table' and rawget(obj, '__doc') then
    return rawget(obj, '__doc')(obj, self)
  end
  local name, loc = mty.anyinfo(obj)
  local cmt, code = self:extractCode(loc)
  self:bold(name); self:write': raw '; self:code(ty) self:write'\n'
  if cmts and cmt and #cmt > 0 then
    for _, c in ipairs(cmts) do self:write(c) self:write'\n' end
  end
end

--- Get cxt documentation for symbol.
M.Main = mty'Main'{
  __cmd='doc',
  'to [string|file]: where to write output.',
}

--- usage: [$doc{'any.symbol', '--to=optionalOutput.cxt'}]
function M.Main:__call()
  info('doc %q', self)
  assert(#self > 0, 'usage: doc any.symbol')
  local d = M.Doc{to=assert(shim.file(self.to, io.stderr))}
  for _, name in ipairs(self) do
    local obj = M.find(name)
    d(name, obj); d:write'\n'
  end
end

getmetatable(M).__call = function(_, args)
  return M.Main(shim.parseStr(args))()
end
if MAIN == M then return ds.main(shim.run, M.Main, shim.parse(arg)) end
return M

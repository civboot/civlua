
local mty = require'metaty'
local ds  = require'ds'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = mty.lrequire'pegl'

local M = {}

local function extendEndPat(repr, pat, tk)
  local len = tk.c2 - tk.c1 + 1
  return repr..string.rep('-',  len),
         pat ..string.rep('%-', len)
end

-----------------
-- Pegl Definition

-- A string that ends in a closed bracket and handles balanced brackets.
-- Note: the token does NOT include the closing bracket.
M.bracketedStr = function(p)
  local l, c = p.l, p.c
  local nested = 1
  mty.pnt('Enter bracketed Str')
  while nested > 0 do
    local c1, c2 = p.line:find('[%[%]]', p.c)
    if c2 then
      p.c = c2 + 1
      local c = p.line:sub(c1, c2)
      nested = nested + ((c == '[') and 1 or -1)
    else
      p:incLine()
      if p:isEof() then error(
        "Reached EOF but expected balanced string"
      )end
    end
  end
  mty.pnt('Exit bracketed Str')
  p.c = p.c - 1 -- parser starts at closing bracket
  return Token:encode(p, l, c, p.l, p.c - 1)
end

local namePat = Pat[==[[_.-:("')=/%w]+]==]

M.extend = Pat{'%-+', kind='extend'}
M.attrSym = Key{kind='attrSym', {
  '!',             -- comment
  '*', '/', '_',   -- bold, italic, underline
  ':',             -- define node
}}
M.keyval = {
  {namePat, kind='key'},
  Maybe{'=', '%S+', kind='value'},
}
M.attr = Or{
  M.extend,
  M.attrSym,
  M.keyval,
}

M.attrs = {'{', Many{M.attr}, '}', kind='attrs'}

M.CTRL = {
  ['*'] = '*',  ['/'] = '/',  ['_'] = '_',

  ['{'] = M.attrs,
  ['-'] = M.extend,
  ['<'] = {'<', Pat{'[^>]*', kind='url'}, '>'},

  -- completes the block
  ['!'] = {'!',  M.bracketedStr, kind='comment'},
  ['#'] = {'#',  M.bracketedStr, kind='code'},
  ['.'] = {'%.', M.bracketedStr, kind='path'},
  ['@'] = {'@',  namePat,        kind='fetch'},
}
local VALID_CTRL = {}
for k in pairs(M.CTRL) do add(VALID_CTRL, k) end
table.sort(VALID_CTRL)
VALID_CTRL = mty.fmt(VALID_CTRL)

M.text = Pat{'[^%[%]]+', kind='text'}
M.content = Or{M.text} -- will include ctrl, but used in ctrl
M.ctrl = function(p)
  local start = p:consume'^%['; if not start then return end
  local ctrlTk = assert(p:peek'.', 'EOF after [')
  local ctrlCh = p:tokenStr(ctrlTk)
  local ctrlSpec = mty.assertf(M.CTRL[ctrlCh],
    "Unrecognized character after '[': %q, expected: %s",
    ctrlCh, VALID_CTRL
  )
  local n = p:parse(ctrlSpec);
  assert(n)

  -- if not n then p:error(
  --   "parser expected: %s\nGot: %s",
  --   mty.fmt(ctrlSpec), p.line:sub(p.c)
  -- )end

  local endRepr, endPat = ']', '%]'
  if n.kind == 'extend' then
    endRepr, endPat = extendEndPat(endRepr, endPat, n)
  elseif n.kind == 'attrs' then for _, attr in ipairs(n) do
    if attr.kind == 'extend' then
      endRepr, endPat = extendEndPat(endRepr, endPat, attr)
    end
  end end
  local out = {kind='ctrl', start, n}
  while true do
    mty.assertf(not p:isEof(), "expected closing %q", endRepr)
    n = p:consume(endPat); if n then add(out, n); return out end
    add(out, assert(p:parse(M.content)))
  end
end
add(M.content, M.ctrl)

M.src = {Many{M.content}, Eof}
M.fmtKind = ds.copy(pegl.RootSpec.fmtKind)
M.fmtKind.text = function(t, f) add(f, sfmt('T%q', t[1])) end
M.root = pegl.RootSpec{fmtKind = M.fmtKind}

-- Create text node for testing
function M.T(text) return {kind='text', text} end

return M

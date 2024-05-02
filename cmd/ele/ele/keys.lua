local pkg = require'pkglib'
local term = pkg'civix.term'
local byte, char, yield = string.byte, utf8.char
local codepoint = utf8 and utf8.codepoint or byte

local M = {}

M.KEY_INSERT = {
  ['tab']       = '\t',
  ['return']    = '\n',
  ['space']     = ' ',
  ['slash']     = '/',
  ['backslash'] = '\\',
  ['caret']     = '^',
}

M.insertKey = function(k)
  return (1 == utf8.len(k) and k) or M.KEY_INSERT[k]
end

local VALID_KEY = {}
-- m and i don't have ctrl variants
VALID_KEY['m'] = 'ctrl+m == return';
VALID_KEY['i'] = 'ctrl+i == tabl'
for c=byte'A', byte'Z' do VALID_KEY['^'..char(c)] = true end
for c     in pairs(M.KEY_INSERT)  do VALID_KEY[c] = true end
for _, kc in pairs(term.CMD)      do VALID_KEY[kc] = true end
for _, kc in pairs(term.INP_SEQ)  do VALID_KEY[kc] = true end
for _, kc in pairs(term.INP_SEQO) do VALID_KEY[kc] = true end
VALID_KEY['unknown'] = true
M.VALID_KEY = VALID_KEY

local function assertKey(key)
  assert(#key > 0, 'empty key')
  local v = VALID_KEY[key]; if true == v then return key end
  if #key == 1 then
    local cp = codepoint(key)
    if cp <= 32 or (127 <= cp and cp <= 255) then error(
      string.format(
        '%q is not a printable character for u (in key %q)',
        ch, key)
    )end; return key
  end
  if v then error(string.format('%q not valid key: %s', key, v))
  else error(string.format('%q not valid key', key)) end
end

local function fixKeys(keys)
  for i, k in ipairs(keys) do
    if string.match(k, '^%^') then k = string.upper(k) end
    assertKey(k); keys[i] = k
  end; return keys
end; M.fixKeys = fixKeys

M.parseKeys = function(key)
  local out = {}; for key in string.gmatch(key, '%S+') do
     table.insert(out, key)
  end; return fixKeys(out)
end

return M

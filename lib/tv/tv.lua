-- TV: tabulated values. See README.cxt for details.
local M = mod and mod'tv' or {}

local mty = require'metaty'
local ds = require'ds'
local push, concat = table.insert, table.concat
local rep = string.rep

local ENCODE = {['\n'] = '\\n', ['\t'] = '\\t'}
local DECODE = {n='\n', t='\t', ['\\']='\\'}
for c=1,9 do -- \1-9 is that many backslashes
  DECODE[string.char(string.byte'0' + c)] = rep('\\', c)
end

-----------
-- Encode

-- encode any number of backslashes
M.encodeBackslashes = function(str)
  local num = #str; if num == 1 then return '\\\\' end
  local e = rep('\\9', num // 9); num = num % 9
  return (num == 0) and e or (e..'\\'..num)
end
local eback = M.encodeBackslashes
M.encodeCell = function(v, ser)
  if v == nil then return ''   end
  if v == ''  then return '\\' end
  return (ser or tostring)(v)
    :gsub('\\+', eback):gsub('[\n\t]', ENCODE)
end
M.encodeComment = function(comment) --> string
  local out = {}; for _, line in ds.split(comment, '\n') do
    push(out, "' "..line)
  end
  return table.concat(out, '\n')
end
M.encodeTypes = function(types) --> string
  return ': '..table.concat(types, '\t: ')
end
M.encodeNames = function(names) --> string
  return '| '..table.concat(names, '\t| ')
end
M.encodeRow = function(names, row, types, serdeMap)
  local ec, out = M.encodeCell, {}
  for i, name in ipairs(names) do
    local v = row[name]
    local ser = serdeMap[types and types[i]]
    out[i] = ec(v, ser and ser.ser)
  end
  return table.concat(out, '\t')
end

-- Encoder. Example:
-- local enc = tv.Encoder{}
-- f:write(enc:comment'some comment',    '\n')
-- f:write(enc:types{'int', 'string'},   '\n')
-- f:write(enc:names{'id',  'username'}, '\n')
-- for _, v in ipairs(myData) do
--   f:write(enc(v), '\n')
-- end
M.Encoder = mty'Encoder' {
  'serdeMap [SerdeMap]',
  '_types[table]', '_names[table]'
}

-- encode a comment. Only valid in the header
M.Encoder.comment = function(enc, s)
  assert(not enc._names)
  return M.encodeComment(s)
end

-- Set the types of the encoder and return the
-- string to write.
M.Encoder.types = function(enc, types) --> string
  assert(not (enc._types or enc._names))
  local o = M.encodeTypes(types); enc._types = types
  return o
end

-- Set the names of the encoder and return the
-- string to write.
M.Encoder.names = function(enc, names) --> string
  assert(not enc._names)
  local o = M.encodeNames(names); enc._names = names
  return o
end

M.Encoder.__call = function(enc, row)
  return M.encodeRow(enc._names, row, enc._types, enc.serdeMap)
end

-----------
-- Decode
do
-- Interface for serialization/deserialization of types.
M.Serde = mty'Serde'{
  'ser [function(v) -> string]: serializer', ser=tostring,
  'de  [function(string) -> v]: deserializer',
}
local BOOL = {
  t=true,  ['true']=true,   y=true,  yes=true,
  f=false, ['false']=false, n=false, no=false,
}
M.bool    = M.Serde { de = function(s)
  local b = BOOL[s]; if b ~= nil then return b end
  error('invalid bool: '..s)
end }
M.integer = M.Serde { de = math.tointeger }
M.number  = M.Serde { de = tonumber }
M.string  = M.Serde { de = function(s) return s end }
end -- Serde

-- Overrideable map of type serializer/deserializer objects.
-- Keys should be the "type name", values must have the following
-- fields:
M.SerdeMap = mty'SerdeMap'{}
getmetatable(M.SerdeMap).__index = nil
M.SerdeMap.__newindex = nil
M.SerdeMap.bool    = M.bool
M.SerdeMap.integer = M.integer
M.SerdeMap.number  = M.number
M.SerdeMap.string  = M.string
M.SerdeMap.epoch   = M.number

-- decode the matched pattern
M.cellmatch = function(backs, esc)
  local nbacks = #backs
  if esc == '\\'     then return rep('\\', (nbacks + 1) // 2) end
  if nbacks % 2 == 0 then return rep('\\', nbacks // 2)..esc  end
  return rep('\\', (nbacks - 2) // 2)
       ..(DECODE[esc] or ('\\'..esc))
end
local cellmatch = M.cellmatch

-- decode a tv cell as a string
M.decodeCell = function(cell, de)
  if cell == ''   then return nil end
  local d = (cell == '\\') and '' or cell:gsub('(\\+)(.)', cellmatch)
  if de then return de(d) end
  return d
end
M.decodeRow = function(names, row, types, serdeMap)
  local i, out, dc = 1, {}, M.decodeCell
  for _, cell in ds.split(row, '\t') do
    local de = serdeMap[types and types[i]]
    out[names[i] or i] = dc(cell, de and de.de)
    i = i + 1
  end
  return out
end

M.decodeHeader = function(start, str)
  if not str:match('^'..start) then error('must start with '..start) end
  start = start..'%s*'
  local out = {}; for _, v in ds.split(str, '\t') do
    v = v:gsub(start, '')
    push(out, v)
  end
  return out
end

M.Decoder = mty'Decoder' {
  'serdeMap [SerdeMap]', serdeMap=M.SerdeMap,
  '_types [table]: column types (strings)',
  '_names [table]: column names (strings)',
}
-- decode a row of types
M.Decoder.types = function(dec, str)
  assert(not dec._types, 'types already loaded')
  dec._types = M.decodeHeader(':', str)
  return dec.types
end
-- decode a row of names
M.Decoder.names = function(dec, str)
  assert(not dec._names, 'names already loaded')
  dec._names = M.decodeHeader('|', str)
  return dec.names
end
-- load from file
-- Example: dec:load(open'thing.tv')
M.Decoder.load = function(dec, file) --> Decoder
  while true do
    local line = assert(file:read'l', 'EOF reached before "|names"')
    if     line:sub(1,1) == "'" then -- comment, ignore
    elseif line:sub(1,1) == ':' then dec:types(line)
    elseif line:sub(1,1) == '|' then dec:names(line); return dec
    else error'"|names" line not found' end
  end
end

M.Decoder.__call = function(dec, line)
  return M.decodeRow(dec._names, line, dec._types, dec.serdeMap)
end

-- store(file, t, names=orderedKeys(t[1]), types=nil)
-- simple store function
M.store = function(file, t, names, types, serdeMap) --> encoder
  local enc = M.Encoder{serdeMap=serdeMap or M.SerdeMap}
  if types then file:write(enc:types(types), '\n') end
  file:write(enc:names(names or ds.orderedKeys(t[1])), '\n')
  for _, v in ipairs(t) do file:write(enc(v), '\n') end
  return enc
end

-- load all the data and return it as a table
M.load = function(file, serdeMap) --> data, decoder
  local out, dec = {}, M.Decoder{serdeMap=serdeMap or M.SerdeMap}
  dec:load(file)
  for line in file:lines'l' do push(out, dec(line)) end
  return out, dec
end

return M

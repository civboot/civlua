--- utf8 stream decoding.
--- Get the length by decodelen(firstbyte), then decode the whole character
--- with decode(dat)
local M = mod and mod'ds.utf8' or {}

local U8LEN = {}
do
  local char, slen = utf8.char, utf8.len
  for b=0,15 do U8LEN[        b << 3 ] = 1 end -- 0xxxxxxx: 1byte utf8
  for b=0,3  do U8LEN[0xC0 | (b << 3)] = 2 end -- 110xxxxx: 2byte utf8
  for b=0,1  do U8LEN[0xE0 | (b << 3)] = 3 end -- 1110xxxx: 3byte utf8
                U8LEN[0xF0           ] = 4     -- 11110xxx: 4byte utf8
end
local U8MSK = {0x7F, 0x1F, 0x0F, 0x07} -- len -> msk

--- given the first byte return the number of bytes in the utf8 char
M.decodelen = function(firstbyte) return U8LEN[0xF8 & firstbyte] end

--- decode utf8 data (table) into an integer.
--- Use [$utf8.char] (from lua's stdlib) to turn into a string.
M.decode = function(dat) --> int
  local c = U8MSK[#dat] & dat[1]
  for i=2,#dat do c = (c << 6) | (0x3F & dat[i]) end
  return c
end

return M

-- small script which prints out the prime numbers just before each power of
-- two greater than 8 as a C array. These use the division test since speed
-- isn't important.

local sqrt = math.sqrt

local function isprime(n)
  if n % 2 == 0 then return false end
  if n % 3 == 0 then return false end

  local d, last = 5, sqrt(n)
  while d < last do
    if n % d == 0 then return false end
    d = d + 2
    if n % d == 0 then return false end
    d = d + 4 -- +2 would have been divisible by 3
  end
  return true
end

local po2 = {}
for n=8,32 do
  local p = 1 << n
  p = p - 1
  while not isprime(p) do p = p - 2 end
  print(n, string.format('% 8x', p), p)
  table.insert(po2, p)
end
local w = function(s) io.stdout:write(s) end
local f = string.format

w'// the previous prime for 2^8 to 2^32\n'
w'// generated from po2prime.lua\n'
w'uint32_t po2primes[] = {\n'
for r=1,6 do
  local c = (r-1)*4 + 1
  w'  '
  for c=c,c+3 do w(f('%-11s ', f('0x%x,', po2[c]))) end
  w'\n'
end
w'};\n'


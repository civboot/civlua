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
for r=1,3 do
  local c = (r-1)*8 + 1
  w'  '
  for c=c,c+7 do w(f('% 10s, ', f('0x%x', po2[c]))) end
  w'\n'
end
w'}\n'
w[[
// given a power of 2 return the prime just before it
// the min/max values are the primes of 2^8 and 2^32 respectively.
static uint32_t prev_po2_prime(uint32_t po2) {
  if(po2 <= 8)  return po2primes[0];
  if(po2 >= 32) return po2primes[32-8];
  return po2primes[po2-8];
}

// find the power-of-2 that is >= val and return the prime just before
// that.
static int prevpo2(uint32_t val) {
  if(val < 0x100) return po2primes[0];
  for(int po2=8; po2 < 31; po2++) {
    if((1<<po2) >= val) return po2primes[po2 - 8];
  }
  return po2primes[32-8];Q
}
]]


local T = require'civtest'
local push = table.insert

T'kev'; do
  local kev = require'lines.kev'
  local t = {a='value a', b='value b', e=''}
  local r = {'a=value a', 'b=value b', 'e='}
  T.eq(r, kev.to(t))
  T.eq(t, kev.from(r))
  push(r, 'this has no equal sign and is ignored')
  T.eq(t, kev.from(r))
end

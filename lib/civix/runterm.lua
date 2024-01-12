METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local civix = require 'civix'
local term = require 'civix.term'
local sfmt = string.format

local mode = arg[1] or 'view'
print(string.format('runterm mode=%s', mode))
local period = tonumber(arg[2] or '0.5')

local outpath = '.out/out.txt'
local out = assert(io.open(outpath, 'w'), 'could not open '..outpath)
print('Logs in', outpath)

local function entered() mty.pnt('?? entered raw mode') end
local function exited()  mty.pnt('?? exited raw mode')  end
if mode == 'raw' then
  print('Starting raw. Ctrl+C to exit.')
  term.enterRawMode(out, out, entered, exited)
  mty.pnt('?? Starting raw input loop')
  local inp = term.rawinput()
  while true do
    local c = inp()
    out:write('?? raw: ', c, '\n'); out:flush()
    if c == 3 then break end
  end
  term.exitRawMode()
  os.exit(0)
elseif mode == 'input' then
  print('?? Starting input. Ctrl+C to exit.')
  term.enterRawMode(out, out, entered, exited)
  local inp = term.niceinput()
  while true do
    local c = inp()
    out:write('?? key: ', c, '\n'); out:flush()
    if c == '^C' then break end
  end
  term.exitRawMode()
  os.exit(0)
else
  assert(mode == 'view', 'Expected mode {view,raw,input} got: ' .. mode)
  local t = term.Term;
  t:start(out, out, entered, exited)
  local h, w = t:size();
  t:golc(1, 1); t:clear()
  local p = function()
    io.flush(); civix.sleep(period)
  end
  local msg = sfmt('h=%s  w=%s', h, w)
  p()
  out:write(msg); t:write(msg)
  p()
  t:golc(3, 3); t:write('wrote on 3, 3'); p()
  t:golc(5, 3); t:write('wrote on 5, 3'); p()
  t:golc(8, 1); t:write('wrote on 8, 1'); p()
  t:golc(9, 1); t:write('clear EoL:CLEARING THIS')
  p(); t:cleareol(9, 11); p()
  civix.sleep(period * 3)
  t:clear(); t:golc(1, 1)
  t:stop()
end

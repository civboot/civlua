-- helpers for testing ele and related libraries
M = mod and mod'ele.testing' or {}

local info = require'ds.log'.info
local term = require'civix.term'

local x = require'civix'

M.SLEEP = 0
local function sleep()
  if M.SLEEP > 0 then x.sleep(M.SLEEP) end
end

function M.runterm(fn)
  local stdout, stderr = io.tmpfile(), io.tmpfile()
  term.Term:start(stdout, stderr)
  local ok, err = xpcall(fn, debug.traceback, term.Term)
  term.Term:stop(); io.stderr:write'\n'
  info('runterm '..(ok and 'DONE' or ('ERROR:\n'..err)))
  stdout:flush();   stderr:flush()
  stdout:seek'set'; stderr:seek'set'
  local out, err = stdout:read'a', stderr:read'a'
  assert(#out > 0)
  if #out > 0 then info('STDOUT:\n'..out) end
  if #err > 0 then info('STDERR:\n'..err) end
  stdout:close(); stderr:close()
  assert(ok, err)
end

-- fill height and width diagonally
function M.diagonal(T)
  local l, c, l2, c2 = 1, 1, T:size()
  assert(l2 and c2)
  local txt = string.format('[height=%s width=%s]', l2, c2)
  while (l <= l2) and (c + #txt <= c2) do
    T:golc(l, c); T:write(txt); T:flush()
    l = l + 1; c = c + 4
    x.sleep(M.SLEEP)
  end
end

-- set lefthand side
function M.setleft(T, left)
  for l=1,(T:size()) do
    T:golc(l, 1) T:write(left); T:cleareol(); T:flush(); sleep()
  end
end

-- create a grid of column numbers (final digit)
function M.setcolgrid(T, c1)
  local l2, c2 = T:size()
  for l=1,l2 do
    for c=c1+1,c2,2 do
      c = c - (l % 2)
      T:set(l, c, tostring(c):sub(-1)); T:flush()
    end
    sleep()
  end
end

return M

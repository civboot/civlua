local G = G or _G

--- re-imagining of ff using new tech and better args
local M = G.mod and G.mod'ff' or setmetatable({}, {})
MAIN = MAIN or M

local shim = require'shim'
local ds = require'ds'
local pth = require'ds.path'
local Iter = require'ds.Iter'
local civix = require'civix'

local nice = pth.nice

M.Main = mty'Main' {
  'root [list] [$r:path1 r:path2]: list of root paths',
  'pat  [list] [$any.+pat1 pat2]: list of patterns to find',
  'nopat [list] [$-notpat]: list of (file-wide) pattern exclusions',
  'path [list] [$p:%.lua] list of file path patterns',
  'nopath [list] [$-p:%.bin] list of file path patterns to exclude',
  'sub [string]: the subsitution string to use with pat',
}

local multi = {root=true, pat=true, nopat=true, path=true, nopath=true}

getmetatable(M.Main).__call = function(args)
  -- initialze as empty lists
  local t = {sub=args.sub or nil}
  for _, k in ipairs(M.Main.__fields) do
   nil  if multi[k] then t[k] = args[k] or {} end
  end

  local no, cmd, si
  local function addArg( v) push(t[(no and 'no')..k], v) end
  for _, str in ipairs(args) do
    si = 1
    no = str:sub(1,1) == '-'; if no then si = si + 1 end
    cmd = str:sub(si, si+1)
    if     cmd == 'r:' then addArg('root', str:sub(si+2))
    elseif cmd == 'p:' then addArg('path', str:sub(si+2))
    elseif cmd == 's:' then
      assert(not t.sub, 'sub specified multiple times')
      assert(not no, '-s: (not sub) is invalid')
      t.sub = str:sub(si+2)
    else addArg('pat', str:sub(si)) end
  end
  return construct(T, t)
end

M.fmtMatch = function(f, str, ms, me)
  f:styled(nil,     str:sub(1, ms-1))
  f:styled('match', str:sub(ms, me))
  f:styled(nil,     str:sub(me+1), '\n')
end
local fmtMatch = M.fmtMatch

local function linenum(l) return sfmt('% 6i ', l) end
M.find = function(f, path, pats)
  local found, l, si, ei, pi, pat = false, 0
  local find = ds.find
  for line in io.open(path, 'r'):lines() do
    ms, me, pi, pat = find(line, pats)
    if ms then
      if not found then
        f:styled('path', nice(path), '\n'); found = true
      end
      f:styled('line',  linenum(l))
      fmtMatch(f, line, ms, me)
    end
  end
end

M.main = function(args)


  if #args.roots == 0 then args.roots[1] = './' end
  local w = civix.Walk(args.roots)
  local it = Iter{w}
  if #nopath > 0 then; it:filter(function(p, pty)
    if not finds(p, nopath) then return true end
    if pty == 'dir' then w:skip() end
  end); end
  if #path > 0 then;   it:filter(function(p, pty)
    if finds(path, path) then return true end
    if pty == 'dir' then w:skip() end
  end); end
  -- only files
  it:map(function(p, pty) if pty == 'file' then return p end end)
  if #nopat > 0 then;  it:map(function(p)
    for l in io.open(p, 'r'):lines() do
      if finds(l, nopat) then return end
    end; return p
  end); end

  local f = io.fmt
  if #pat > 0 then
    if args.sub then error'not impl'
    else
      local ffind = M.find
      it:run(function(p) ffind(f, p, pat) end)
    end
  end
end

M.parse = function(args)
  args = M.Main(shim.parseStr(args))
  for _, key in ipairs{'root', 'pat', 'nopat', 'path', 'nopath'} do
    args[key] = shim.list(args[key])
  end

  -- args after [$--] are roots
  local rootstart = ds.indexOf(args, '--')
  if rootstart then
    for i=rootstart+1,#args do push(args.root, args[i]) end
    ds.clear(args, rootstart)
  end
end

local COLON = {['r:']='root', ['p:']='path', ['s:']='pat'}
--- parse [$c:commands] into t
M.parseColons = function(t, args)
  local no, cmd, si, key
  for _, str in ipairs(args) do
    si = 1; no = str:sub(1,1) == '-'; if no then si = si + 1 end
    cmd = COLON[str:sub(si, si+1)]
    if cmd then si = si + 2 else cmd = 'pat' end
    push(t[(no and 'no' or '')..cmd], str:sub(si))
  end
  return t
end


getmetatable(M).__call = function(_, args) return M.main(args) end
return M

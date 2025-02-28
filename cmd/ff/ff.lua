local G = G or _G

--- re-imagining of ff using new tech and better args
local M = G.mod and G.mod'ff' or setmetatable({}, {})
MAIN = MAIN or M

local shim = require'shim'
local mty  = require'metaty'
local ds   = require'ds'
local log  = require'ds.log'
local pth  = require'ds.path'
local Iter = require'ds.Iter'
local civix = require'civix'
local acs = require'asciicolor.style'
local fassert = require'fail'.assert

local sfmt, gsub = string.format, string.gsub
local push = table.insert
local construct = mty.construct
local nice = pth.nice

local fmtMatch, fmtSub

-- TODO: '-' should mean --stdin. Also support stdin

--- find-fix: find (and optionally replace) patterns
---
--- Colon args:[+
--- * [$ r:some/dir/]: same as [$--root=some/dir/]
--- * [$ p:a_path.*pattern]: same as [$--path=some/dir]
--- * [$-p:a_path.*pattern]: same as [$--nopath=some/dir]
--- ]
---
--- Examples:[{## sh}
--- ff some.*pattern  # search recursively in local dir
--- ff r:some/dir/ some.*pat -not.*pat p:some%.path -p:not%.path]
--- ]##
---
--- ff's replacing functionality is intended to be used incrementally:[+
--- * use [$--sub=whatever] to see what changes will happen
--- * only use [$--mut] when everything looks correct
--- ]
---
--- Note that all directories/ always end with [$/]
M.Main = mty'Main' {
  'root [list] [$r:path1 r:path2]: list of root paths',
  'pat  [list] [$any.+pat1 pat2]: list of patterns to find',
  'nopat [list] [$-notpat]: list of (file-wide) pattern exclusions',
  'path [list] [$p:%.lua] list of file path patterns',
  'nopath [list] [$-p:%.bin] list of file path patterns to exclude.\n'
  .."default: exclude dirs starting with '.'. Disable default by setting "
  ..'to an empty string, i.e. [$--nopath=]',
  'sub [string]: the subsitution string to use with pat',
  'mut [bool]: mutate files (used with sub)',
  'dirs [bool]: show all non-excluded directories',
}


--- find patterns in path.
--- If there is a match then the path is logged to [$io.stdout] and the matches
--- to [$io.fmt].
M.find = function(path, pats, sub) --> boolean
  local found, l, find, ms, me, pi, pat = false, 0, ds.find
  local f, sf = io.fmt, acs.Fmt{to=io.stdout}
  for line in io.lines(path) do
    l, ms, me, pi, pat = l + 1, find(line, pats)
    if ms then
      if not found then
        sf:styled('path', nice(path), '\n'); sf:flush()
        found = true
      end
      fmtMatch(f, l, line, ms, me)
      if sub then
        local after = assert(gsub(line, pat, sub))
        fmtSub(f, line, after)
      end
    end
  end
  return found
end

--- perform replacement of [$pats] with [$sub], writing to [$to]
M.replace = function(path, to, pats, sub)
  local find, ms, me, pi, pat = ds.find
  for line in io.lines(path, 'L') do
    ms, me, pi, pat = find(line, pats)
    to:write(ms and gsub(line, pat, sub) or line)
  end
end

--- Get an iterator of matching paths.
---
--- ["WARNING: this also writes to io.fmt and io.stdout]
M.iter = function(args) --> Iter
  args = M.Main(args)
  if #args.root == 0 then args.root[1] = pth.cwd() end
  log.info('ff %q', args)
  local sf = acs.Fmt{to=io.stdout}

  local w = civix.Walk(args.root)
  local it, ffind, finds = Iter{w}, M.find, ds.find
  -- check nopath patterns
  if #args.nopath > 0 then; it:map(function(p, pty)
    if not finds(p, args.nopath) then return p, pty end
    if pty == 'dir' then w:skip() end
  end); end
  -- show/no-show dirs
  if args.dirs then;   it:map(function(p, pty)
      if pty == 'dir' then sf:styled('path', nice(p), '\n') end
      return p, pty
    end)
  else
    it:map(function(p, pty) if pty ~= 'dir' then return p, pty end end)
  end
  -- check path patterns
  if #args.path > 0 then;   it:map(function(p, pty)
    if (pty == 'dir') or finds(p, args.path) then return p, pty end
  end); end
  -- check for nopat
  if #args.nopat > 0 then
    local nopat = args.nopat
    it:map(function(p, pty)
      if pty == 'dir' then return p, pty end
      for l in io.lines(p) do
        if finds(l, nopat) then return end
      end; return p, pty
    end)
  end

  -- find pattern or sub in file
  local pat, sub = args.pat, args.sub
  if #pat > 0 then
    it:map(function(p, pty)
      if (pty == 'dir') or ffind(p, pat, sub) then return p, pty end
    end)
  end

  -- perform actual replacement mutation
  if sub and args.mut then
    local replace = M.replace
    it:map(function(p, pty)
      if pty == 'file' then
        local subPath = p..'.SUB'
        local to = fassert(io.open(subPath, 'w+'))
        if to:seek'end' ~= 0 then error(sfmt(
          '%s already exists', subPath
        ))end
        replace(p, to, pat, sub)
        to:flush(); to:close(); civix.mv(subPath, p)
      end
      return p, pty
    end)
  end
  return it
end

-----------------------
-- Parsing Utils

-- construct main from args
getmetatable(M.Main).__call = function(T, args)
  args = shim.parseStr(args)
  for _, k in ipairs{'root', 'pat', 'nopat', 'path', 'nopath'} do
    args[k] = shim.list(args[k])
  end
  shim.popRaw(args, args.root)
  M.parseColons(args)
  if #args.nopath == 0 then args.nopath={'^%..*/', '/%..*/'} end
  local i = 1; while i <= #args.nopath do
    if args.nopath[i] == '' then table.remove(args.nopath, i)
    else i = i + 1 end
  end
  return construct(T, args)
end

local COLON = {['r:']='root', ['p:']='path', ['s:']='pat'}
--- parse [$c:commands] into t
M.parseColons = function(args)
  local no, cmd, si
  for _, str in ipairs(args) do
    si = 1; no = str:sub(1,1) == '-'; if no then si = si + 1 end
    cmd = COLON[str:sub(si, si+1)]
    if cmd then si = si + 2 else cmd = 'pat' end
    push(args[(no and 'no' or '')..cmd], str:sub(si))
  end
  ds.clear(args)
end

-----------------------
-- Logging Utilities
local linenum = function(l) return sfmt('% 6i ', l) end
local AFTER = '   --> '

M.fmtMatch = function(f, l, str, ms, me)
  f:styled('line',  linenum(l))
  f:styled(nil,     str:sub(1, ms-1))
  f:styled('match', str:sub(ms, me))
  f:styled(nil,     str:sub(me+1), '\n')
end
M.fmtSub = function(f, before, after)
  local si, ei = 1, -1
  while before:sub(si,si) == after:sub(si,si) do si = si + 1 end
  while before:sub(ei,ei) == after:sub(ei,ei) do ei = ei - 1 end
  ei = #after + ei + 1
  if ei ~= 0 then
    f:styled('meta', AFTER)
    f:styled('meta', after:sub(1, si-1))
    f:styled(nil,    after:sub(si, ei))
    f:styled('meta', after:sub(ei+1), '\n')
  end
end
fmtMatch, fmtSub = M.fmtMatch, M.fmtSub

M.main = function(args) M.iter(args):run() end
getmetatable(M).__call = function(_, args) --> list of paths
  return M.iter(args):keysTo()
end
return M

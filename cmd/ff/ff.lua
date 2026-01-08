#!/usr/bin/env -S lua
local mty = require'metaty'
local G = mty.G

--- re-imagining of ff using new tech and better args
local M = mty.mod'ff'
G.MAIN = G.MAIN or M; if G.MAIN == M then mty.setup() end

local shim = require'shim'
local mty  = require'metaty'
local ds   = require'ds'
local log  = require'ds.log'
local pth  = require'ds.path'
local Iter = require'ds.Iter'
local civix = require'civix'
local vt100 = require'vt100'

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
--- Examples:[{$$ sh}
--- ff some.*pattern  # search recursively in local dir
--- ff r:some/dir/ some.*pat -not.*pat p:some%.path -p:not%.path]
--- ]$
---
--- ff's replacing functionality is intended to be used incrementally:[+
--- * use [$--sub=whatever] to see what changes will happen
--- * only use [$--mut] when everything looks correct
--- ]
---
--- Note that all directories/ always end with [$/]
M.FF = mty'FF' {
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
  'content [bool]: if false do not show content (only show paths)',
    content=true,
 [[pathsub [string]: the substitution string to rename the path.
   Note: this implies content=false and cannot be used with sub
 ]],
}


--- find patterns in path.
--- If there is a match then the path is logged to [$io.stdout] and the matches
--- to [$io.fmt].
function M.FF:find(path, pats, sub) --> boolean
  local f, sf = io.fmt, vt100.Fmt{to=io.stdout}
  local onlypath = not self.content
  if not civix.exists(path) then
    sf:styled('error', 'Does not exist: '..path, '\n')
    return false
  end
  local found, l, find, ms, me, pi, pat = false, 0, ds.find
  for line in io.lines(path, 'L') do
    l, ms, me, pi, pat = l + 1, find(line, pats)
    if ms then
      if onlypath then
        local path, fs, fe, fi, fpat = path..'\n', find(path, self.path)
        assert(fs)
        fmtMatch(f, nil, path, fs, fe)
        if self.pathsub then
          local after = assert(gsub(path, fpat, self.pathsub))
          fmtSub(f, path, after)
        end
        return true
      end
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
function M.FF:replace(path, to, pats, sub)
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
  local m = M.FF(args)
  if m.pathsub then
    m.content = false
    assert(m.path, 'must set path pattern with path pathsub')
  else m.content = shim.bool(m.content) end
  if not m.content and #m.pat == 0 then m.pat = {''} end
  assert(not (m.sub and m.pathsub), 'must set only one: sub pathsub')
  if #m.root == 0 then m.root[1] = pth.cwd() end
  log.info('ff %q', m)
  local sf = vt100.Fmt{to=io.stdout}

  local w = civix.Walk(m.root)
  local it, finds = Iter{w}, ds.find
  -- check nopath patterns
  if #m.nopath > 0 then; it:map(function(p, pty)
    if not finds(p, m.nopath) then return p, pty end
    if pty == 'dir' then w:skip() end
  end); end
  -- show/no-show dirs
  if m.dirs then;   it:map(function(p, pty)
      if pty == 'dir' then sf:styled('path', nice(p), '\n') end
      return p, pty
    end)
  else
    it:map(function(p, pty) if pty ~= 'dir' then return p, pty end end)
  end
  -- check path patterns
  if #m.path > 0 then;   it:map(function(p, pty)
    if (pty == 'dir') or finds(p, m.path) then return p, pty end
  end); end
  -- check for nopat
  if #m.nopat > 0 then
    local nopat = m.nopat
    it:map(function(p, pty)
      if pty == 'dir' then return p, pty end
      for l in io.lines(p) do
        if finds(l, nopat) then return end
      end; return p, pty
    end)
  end

  -- find pattern or sub in file
  local pat, sub = m.pat, m.sub
  if #pat > 0 then
    it:map(function(p, pty)
      if (pty == 'dir') or m:find(p, pat, sub) then return p, pty end
    end)
  end

  -- perform actual replacement mutation
  if sub and m.mut then
    it:map(function(p, pty)
      if pty == 'file' then
        local subPath = p..'.SUB'
        local to = assert(io.open(subPath, 'w+'))
        if to:seek'end' ~= 0 then error(sfmt(
          '%s already exists', subPath
        ))end
        m:replace(p, to, pat, sub)
        to:flush(); to:close();
        civix.mv(subPath, p)
      end
      return p, pty
    end)
  end

  if m.pathsub and m.mut then
    it:map(function(p, pty)
      local p, fs, fe, fi, fpat = p..'\n', find(p, self.path)
      assert(fs)
      civix.forceMv(p, gsub(p, fpat, self.pathsub))
    end)
  end
  return it
end

-----------------------
-- Parsing Utils

-- construct main from args
getmetatable(M.FF).__call = function(T, args)
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

local splitMatch = function(str, ms, me) --> beg, mat, end_
  local beg, mat = str:sub(1,ms-1), str:sub(ms,me)
  local end_     = str:sub(me+1)
  local hasNL = str:sub(-1) == '\n'
  if hasNL then
    if end_ == '' then mat = mat:sub(1,-2)
    else end_ = end_:sub(1,-2) end
  else end_ = end_..'[EOL]' end
  return beg, mat, end_
end

M.fmtMatch = function(f, l, str, ms, me)
  local beg, mat, end_ = splitMatch(str, ms, me)
  f:styled('line',  l and linenum(l) or '       ')
  f:styled(nil,     beg)
  f:styled('match', mat)
  f:styled(nil,     end_, '\n')
end
M.fmtSub = function(f, before, after)
  local si, ei = 1, -1
  while before:sub(si,si) == after:sub(si,si) do si = si + 1 end
  while before:sub(ei,ei) == after:sub(ei,ei) do ei = ei - 1 end
  ei = #after + ei + 1
  if ei == 0 then return end
  local beg, mat, end_ = splitMatch(after, si, ei)
  f:styled('meta', AFTER)
  f:styled('meta', beg)
  f:styled(nil,    mat)
  f:styled('meta', end_, '\n')
end
fmtMatch, fmtSub = M.fmtMatch, M.fmtSub

M.main = function(args)
  shim.runSetup()
  M.iter(args):run()
end
if G.MAIN == M then M.main(shim.parse(G.arg)) end

getmetatable(M).__call = function(_, args) --> list of paths
  return M.iter(args):keysTo()
end
return M

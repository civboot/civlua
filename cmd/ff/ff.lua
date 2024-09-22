#!/usr/bin/env -S lua -e "require'pkglib'()"
--- ff module (see [$ff.Main] for docs)
local M = mod and mod'ff' or setmetatable({}, {})
MAIN = MAIN or M

local shim = require'shim'
local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local Iter = require'ds.Iter'
local ix = require'civix'
local push = table.insert
local fd = require'fd'
local vt100 = require'vt100'
local AcWriter = require'vt100.AcWriter'
local astyle = require'asciicolor.style'
local doc = require'doc'

local s = ds.simplestr
local sfmt = string.format

--- A simple utility to find and fix files and file-content
---
--- List args: [$%patARg pathArg1 pathArg2]
---
--- [*Examples (bash):] [{## lang=bash}
---   ff path                   # print files at path (recursively)
---   ff path --dir             # also print directories
---   ff path --depth=3         # recurse to depth 3 (default=1)
---   ff path --depth=          # recurse infinitely (depth=-1)
---   ff path --depth=-1        # recurse infinitely (depth=-1)
---   ff path --pat='my%s+name' # find Lua pattern like "my  name" in files at path
---   ff path %my%s+name        # shortcut for --pat=my%s+name
---   ff path %my%s+name --matches=false  # print paths with match only
---   ff path %(name=)%S+ --sub='%1bob'   # change name=anything to name=bob
---   # add --mut or -m to actually modify the file contents
---   ff path --path='%.txt'    # filter to .txt files
---   ff path --path='(.*)%.txt' --mv='%1.md'  # rename all .txt -> .md
---   # rename OldTestClass -> NewTestClass, 'C' is not case sensitive.
--- ]##
---
--- [*Special:] [$indexed %arg will be converged to --pat=arg]
---
--- [*Shorts:] [##
---   d: --dirs=true
---   p: --plain=true
---   m: --mut=true
---   r: --depth='' (infinite recursion)
---   k: --keep_going=true
---   s: --silent=true
---   F: no special features (%pat parsing, etc)
--- ]##
M.Main = mty'Main' {
  'help [bool]: get help',

  -- major inputs
s[[pat[table]:
     (shortcut: %foo ==> --pat=foo)
     content pattern/s which searches inside of files and prints the results.
     If there are multiple [$pat] then ANY are considered a match and [$sub]
     uses the first match.]],
  -- nopat: todo, skips if nopat is anywhere in the LINE
  'sub    [string]:  substitute pattern to go with pat (see lua\'s gsub)',
  'path   [strings]: file path include pattern (note: "pat"h)',
  'nopath [strings]: file path exclude pattern',
  'incl   [strings]: only include files which contain any incl',
  'excl   [strings]: do not include files which contain any excl',

  -- path/replacement related
  'depth[int]: depth to recurse (default=infinite)',
  'pathsub[string]: substitute path names, passed to cmd (default=mv)',
s[[cmd [string|list|function]
   execute [$cmd(from, to)] on each matching file where [$to] is the result of
   pathsub (or nil if pathsub is not provided)
   If [$cmd] string or list then [$civix.sh] is used to execute via the
   system shell.]],
  'mv[string]: file substitute for [$path]',      -- FIXME: remove mv* and replace with cmd
  'mvcmd[string]: shell command to use for move', --        call string / table / function on each matched
  'mut [bool]: if true files may be modified, else dry run',
    mut=false,
  'keep_going [bool]: (short -k) whether to keep going on errors',

  -- formatting related
  'color [string]: whether to use color [$true|false|always|never]',
  'plain [bool]: no line numbers', plain=false,
  'fpre[string]: prefix characters before printing files',        fpre='',
  'dpre [string]: prefix characters before printing directories', dpre='',

  -- output related
  "silent [bool]: (short -s) don't print errors",
  'log [string|file]: where to log',
  'files[bool]:   log/return files or substituted files.',   files=true,
  'matches[bool]: log/return the matches or substitutions.', matches=true,
  'dirs[bool]:    log/return directories.',                  dirs=false,
  'out [table]: (lua only) stores files/dirs',
}

local function anyMatch(pats, str) --> matching pat, index
  if not pats then return end
  for i, pat in ipairs(pats) do
    if str:find(pat) then return pat, i end
  end
end
local function logPath(log, pre, path, to, mvcmd)
  if pre then log:styled(nil, pre) end
  if to then
    mvcmd = (#mvcmd == 0) and 'mv' or table.concat(mvcmd, ' ')
    log:styled('meta', mvcmd, '  ')
    log:styled('path', pth.nice(path), '\n')
    log:styled('meta', ' -> '); log:styled('path', pth.nice(to),   '\n')
  else
    log:styled('path', pth.nice(path), '\n')
  end
end
local function linenum(l) return sfmt('% 6i ', l) end
local _logMatch = function(args, l, line, m, m2)
  local log = args.log
  if args.sub then
    if not args.plain then
      log:styled('line', (args.fpre or '')..linenum(l))
    end
    log:styled(nil, line, '\n')
  else
    local logl = line
    if args.sub and #line == 0 then logl = '<line removed>' end
    if not args.plain then
      if args.fpre then log:styled(nil, args.fpre) end
      log:styled('line', linenum(l))
    end
    log:styled(nil, logl:sub(1, m-1))
    log:styled('match', logl:sub(m, m2))
    log:styled(nil, logl:sub(m2+1), '\n')
  end
end
local function move(path, to, cmd)
  local dir = pth.last(pth.abs(to))
  if not ix.exists(dir) then ix.mkDirs(dir) end
  if #cmd > 0 then ix.sh(ds.extend(ds.copy(cmd), {path, to}))
  else             ix.mv(path, to) end
end

local function _dirFn(path, args, dirs)
  if anyMatch(args.nopath, path) then return 'skip' end
  if args.dirs then
    if args.log then
      if args.dpre then args.log:styled('meta', args.dpre) end
      args.log:styled('path', pth.nice(path), '\n')
    end
    if dirs then push(dirs, path) end
  end
end

local function _fileFn(path, args, out) -- got a file from walk
  -- check if the path and nopath match
  if anyMatch(args.nopath, path) then return 'skip' end
  local log, pre, files, to = args.log, args.fpre, args.files, nil
  if args.path then
    local pathPat = anyMatch(args.path, path)
    if not pathPat then return end
    if args.mv then to = path:gsub(pathPat, args.mv) end
  end

  -- check whether the file is excluded
  if args.excl and Iter{io.lines(path)}
    :find(function(l) return anyMatch(args.excl, l) end)
    then return end

  -- check whether the file is included
  if args.incl and not Iter{io.lines(path)}
    :find(function(l) return anyMatch(args.incl, l) end)
    then return end

  local pat, sub = args.pat, args.sub
  -- if no patterns exit early
  if #pat == 0 then
    if files and log   then logPath(log, pre, path, to, args.mvcmd) end
    if out.files       then push(out.files, to or path) end
    if args.mut and to then move(path, to, args.mvcmd)  end
    return
  end
  -- Search for patterns and substitution. If mut then write subs.
  local f, tpath; if args.mut and args.sub then
    tpath = (to or path)..'.SUB'; f = io.open(tpath, 'w')
  end

  local l = 1; for line in io.open(path, 'r'):lines() do
    local m, m2, patFound
    for l, p in ipairs(pat) do -- find any matches
      m, m2 = line:find(p); if m then patFound = p; break end
    end
    if not m then -- no match
      if f then f:write(line, '\n') end
      goto continue
    end
    -- matched: record that we found a pat in file on first match
    if files then files = false
      if log             then logPath(log, pre, path, to, args.mvcmd) end
      if out.files       then push(out.files, path)       end
      if args.mut and to then move(path, to, args.mvcmd)  end
    end
    if sub then line = line:gsub(patFound, sub) end
    if args.matches then
      if log         then _logMatch(args, l, line, m, m2) end
      if out.matches then push(out.matches, line) end
    end
    if f and #line > 0 then f:write(line, '\n') end -- match
    ::continue:: l = l + 1
  end
  if f then -- close .SUB file and move it
    f:flush(); f:close()
    ix.mv(tpath, to or path)
    if to then ix.rm(path) end
  end
end

local function _defaultFn(path, ftype, args) if args.log then
  args.log:styled('error', sfmt('?? Unknown ftype=%s: %s', ftype, path), '\n')
end end

local function argPats(args)
  if args.F then return shim.list(args.pat) end
  local pat = {}; for i=#args,1,-1 do local a=args[i];
    if type(a) == 'string' and a:sub(1,1)=='%' then
      push(pat, a:sub(2)); table.remove(args, i)
    end
  end; return ds.extend(ds.reverse(pat), shim.list(args.pat))
end

M.main = function(args)
  args = shim.parseStr(args)
  args.pat = argPats(args)
  if #args == 0 then push(args, '.') end
  if args.sub then
    assert(#args.pat, 'must specify pat with sub')
    assert(not args.mv, 'cannot specify both sub and mv')
  end
  if args.mv then assert(
    args.path, 'must specify path with mv'
  )end
  args.mvcmd = shim.listSplit(args.mvcmd)

  shim.bools(args, 'files', 'matches', 'dirs')
  args.depth  = shim.number(args.depth or -1)
  args.excl   = args.excl  and shim.list(args.excl)
  args.path   = args.path  and shim.list(args.path)
  args.nopath = shim.list(args.nopath, {'/%.[^/]+/'}, {})
  shim.short(args, 'd', 'dirs',  true)
  shim.short(args, 'm', 'mut',   true)
  shim.short(args, 'p', 'plain', true)
  shim.short(args, 'k', 'keep_going', true)
  shim.short(args, 's', 'silent',     true)
  if args.depth < 0 then args.depth = nil end
  args.log = assert(args.log or io.fmt)

  args = M.Main(args)

  args.help = shim.boolean(args.help);
  if args.help then return doc.styleHelp(styler, M.Main) end

  -- args.dpre    = args.dpre or '\n'
  local out = args.out or {
    files = args.files and {} or nil,
    dirs = args.dirs and {} or nil,
    matches = args.matches and {} or nil,
  }
  ix.walk(
    args, {
      file=function(path, _ftype)   return _fileFn(path, args, out)      end,
      dir =function(path, _ftype)   return _dirFn(path, args, out.dirs)  end,
      default=function(path, ftype) return _defaultFn(path, ftype, args) end,
      error=function(path, err)
        if not args.keep_going then error(sfmt('ERROR %s: %s', path, err)) end
        if not args.silent then
          args.log:styled('error', sfmt('! (%s)', err), ' ')
          args.log:styled('path',  path, '\n')
        end
      end
    },
    args.depth
  )
  if args.log then args.log:flush() end
  return out
end
getmetatable(M).__call = function(_, ...) return M.main(...) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M

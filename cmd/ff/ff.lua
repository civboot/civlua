METATY_CHECK = true

local DOC = [[ff: find+fix files
ff is a simple utility to find and fix files and file-content.

References:
  string.find for pat
  string.gsub for sub

Examples (bash):
  ff path                   # print files at path (recursively)
  ff path --dir             # also print directories
  ff path --depth=3         # recurse to depth 3 (default=1)
  ff path --depth=          # recurse infinitely (depth=-1)
  ff path --depth=-1        # recurse infinitely (depth=-1)
  ff path --pat='my%s+name' # find Lua pattern like "my  name" in files at path
  ff path %my%s+name        # shortcut for --pat=my%s+name
  ff path %my%s+name --matches=false  # print paths with match only
  ff path %(name=)%S+ --sub='%1bob'   # change name=anything to name=bob
  # add --mut or -m to actually modify the file contents
  ff path --incl='%.txt'    # filter to .txt files
  ff path --incl='(.*)%.txt' --mv='%1.md'  # rename all .txt -> .md
  # rename OldTestClass -> NewTestClass, 'C' is not case sensitive.

Special:
  indexed %arg will be converged to --pat=arg

Stdout:
  In shell prints files, directories and content matched, depending on
  the arguments.
  In Lua will only print if `log` is specified.

Returns (lua only):
  returns (files, dirs, matches) which may be nil depending on the
  files/dirs/matches arguments.

Short:
  d: --dirs=true
  p: --plain=true
  m: --mut=true
  r: --depth='' (infinite recursion)
  k: --keep_going=true
  s: --silent=true
  F: no special features (%pat parsing, etc)
]]
local M = mod and mod'ff' or {}

local shim = require'shim'
local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'
local push = table.insert
local fd = require'fd'
local vt100 = require'vt100'
local AcWriter = require'vt100.AcWriter'
local astyle = require'asciicolor.style'

local s = ds.simplestr
local sfmt = string.format

-- List arguments: 'path1', 'path2', 'path3'
M.Args = mty'Args' {
  'depth[int]:    depth to recurse (default=infinite)',
  'files[bool]:   log/return files or substituted files.',   files=true,
  'matches[bool]: log/return the matches or substitutions.', matches=true,
  'dirs[bool]:    log/return directories.',                  dirs=false,
s[[pat[table]:
     (shortcut: %foo == --pat=foo; multi: sub uses first)
     content pattern/s which searches inside of files
     and prints the results.]],
  'sub [string]: substitute pattern to go with pat (see lua\'s gsub)',
  'incl[string]:  (multi) file name pattern to include.',
s[[mv[string]:
     file substitute for incl. Renames files (not directories).]],
  'mvcmd[string]: shell command to use for move',
s[[excl [table]:
     (multi: any match excludes)
     exclude pattern (default='/%.[^/]+/' -- aka hidden)]],
  'mut [bool]: if true files may be modified, else dry run',
    mut=false,
  'log: path or (Lua) filehandle to log to.',
  'fpre[string]: prefix characters before printing files',        fpre='',
  'dpre [string]: prefix characters before printing directories', dpre='',
  'plain [bool]: no line numbers', plain=false,
  'color [true|false|always|never]: whether to use color',
  'keep_going [bool]: (short -k) whether to keep going on errors',
  "silent [bool]: (short -s) don't print errors",
}

M.DOC = DOC..'\n#############\n# ARGS\n'
      ..(require'doc'(M.Args):match'.-\n(.-)%-%-+ CODE')

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
local function move(path, to, cmd)
  local dir = pth.last(pth.abs(to))
  if not ix.exists(dir) then ix.mkDirs(dir) end
  if #cmd > 0 then ix.sh(ds.extend(ds.copy(cmd), {path, to}))
  else             ix.mv(path, to) end
end
local function linenum(l) return sfmt('% 6i ', l) end

local function _dirFn(path, args, dirs)
  if anyMatch(args.excl, path) then return 'skip' end
  if args.dirs then
    if args.log then
      if args.dpre then args.log:styled('meta', args.dpre) end
      args.log:styled('path', pth.nice(path), '\n')
    end
    if dirs then push(dirs, path) end
  end
end

local function _fileFn(path, args, out) -- got a file from walk
  -- check if the excl and incl match
  if anyMatch(args.excl, path) then return 'skip' end
  local log, pre, files, to = args.log, args.fpre, args.files, nil
  if args.incl then
    local incl = anyMatch(args.incl, path)
    if not incl then return end
    if args.mv then to = path:gsub(incl, args.mv) end
  end
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
    local m, m2, patFound; for l, p in ipairs(pat) do -- find any matches
      m, m2 = line:find(p); if m then patFound = p; break end
    end; if not m then -- no match
      if f then f:write(line, '\n') end
      goto continue
    end
    if files then files = false -- =false -> pnt only once
      if log             then logPath(log, pre, path, to, args.mvcmd) end
      if out.files       then push(out.files, path)       end
      if args.mut and to then move(path, to, args.mvcmd)  end
    end
    line = (sub and line:gsub(patFound, sub)) or line
    if args.matches then
      if log then
        if sub then
          if not args.plain then
            log:styled('line', (pre or '')..linenum(l))
          end
          log:styled(nil, line, '\n')
        else
          local logl = line
          if sub and #line == 0 then logl = '<line removed>' end
          if not args.plain then
            if pre then log:styled(nil, pre) end
            log:styled('line', linenum(l))
          end
          log:styled(nil, logl:sub(1, m-1))
          log:styled('match', logl:sub(m, m2))
          log:styled(nil, logl:sub(m2+1), '\n')
        end
      end
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

getmetatable(M).__call = function(_, args, out, isExe)
  local argsTy = type(args); args = shim.parseStr(args, true)
  args.pat = argPats(args)
  if #args == 0 then push(args, '.') end
  if args.sub then
    assert(#args.pat, 'must specify pat with sub')
    assert(not args.mv, 'cannot specify both sub and mv')
  end
  if args.mv then assert(
    args.incl, 'must specify incl with mv'
  )end
  args.mvcmd = shim.listSplit(args.mvcmd)

  shim.bools(args, 'files', 'matches', 'dirs')
  args.depth = shim.number(args.depth or -1)
  args.incl  = args.incl and shim.list(args.incl)
  args.excl  = shim.list(args.excl, {'/%.[^/]+/'}, {})
  shim.short(args, 'd', 'dirs',  true)
  shim.short(args, 'm', 'mut',   true)
  shim.short(args, 'p', 'plain', true)
  shim.short(args, 'k', 'keep_going', true)
  shim.short(args, 's', 'silent',     true)
  if args.depth < 0 then args.depth = nil end
  if type(args.log) == 'string' then args.log = io.open(args.log, 'a')
  elseif argsTy == 'string' and not args.log then args.log = io.stdout
  end

  if isExe then local ok;
    ok, args = pcall(M.Args, args)
    if not ok then io.stderr:write(args, '\n'); os.exit(1) end
  else args = M.Args(args) end

  -- args.dpre    = args.dpre or '\n'
  out = out or {
    files = args.files and {} or nil, dirs = args.dirs and {} or nil,
    matches = args.matches and {} or nil,
  }
  if args.log then
    args.log = astyle.Styler{
      acwriter = AcWriter{f=args.log},
      color = shim.color(args.color, fd.isatty(args.log)),
      styles = astyle.dark, -- FIXME: load instead
    }
  end
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

M.exe = function(args, isExe)
  assert(isExe)
  if args.depth == '' then args.depth = -1 end
  args.log = io.stdout
  M(args, {}, true)
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M

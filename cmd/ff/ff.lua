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
  ff path --fpat='%.txt'    # filter to .txt files
  ff path --fpat='(.*)%.txt' --fsub='%1.md'  # rename all .txt -> .md
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
  F: no special features (%pat parsing, etc)
]]
local M = mod and mod'ff' or {}

local shim = require'shim'
local mty = require'metaty'
local ds = require'ds'
local pth = require'ds.path'
local civix = require'civix'
local push = table.insert
local fd = require'fd'
local vt100 = require'vt100'

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
  'fpat[string]:  (multi) file name pattern to include.',
s[[fsub[string]:
     file substitute for fpat. Renames files (not directories).]],
s[[dpat[string]:
     (multi: any includes)
     directory name patterns to include.
     ANY match will cause dir to be included.]],
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
}

M.DOC = DOC..'\n#############\n# ARGS\n'
      ..(require'doc'(M.Args):match'.-\n(.-)%-%-+ CODE')

local Styler = mty'Styler' {
  'f [file]', 'color [bool]',
  'styles [table]',
  'styled [fn(astyle, ...)]',
}
getmetatable(Styler).__call = function(T, t)
  t.styles = t.styles or {
    path='G', match='fZ', meta='d',
    error='R',
  }
  t.styled = t.colored or require'vt100'.colored
  return mty.construct(T, t)
end
Styler.sty = function(w, st, ...)
  if w.color then w.styled(w.f, w.styles[st], ...)
  else            w.f:write(...) end
end
Styler.flush = function(w) return w.f:flush() end
Styler.close = function(w) return w.f:close() end

local function wln(f, msg, pre, i)
  if pre then f:write(pre) end
  if i then f:write(string.format('% 6i: ', i)) end
  f:write(msg); f:write'\n'
end

local function _dirFn(path, args, dirs)
  for _, excl in ipairs(args.excl) do
    if path:find(excl) then return 'skip' end
  end
  if #args.dpat > 0 then local include;
    for _, dpat in ipairs(args.dpat) do
      if path:find(dpat) then include = true; break; end
    end; if not include then return 'skip' end
  end
  if args.dirs then
    if args.log then
      args.log:sty('path', args.dpre or '', pth.nice(path), '\n')
    end
    if dirs then push(dirs, path) end
  end
end

local function _fileFn(path, args, out) -- got a file from walk
  -- check if the excl and fpat match
  for _, excl in ipairs(args.excl) do
    if path:find(excl) then return 'skip' end
  end
  local log, pre, files, to = args.log, args.fpre, args.files, nil
  if args.fpat and not path:find(args.fpat) then return end
  if args.fsub then to = path:gsub(args.fpat, args.fsub) end
  local pat, sub = args.pat, args.sub
  -- if no patterns exit early
  if #pat == 0 then
    if files and log   then
      if pre then log:sty(nil, pre) end
      log:sty('path', pth.nice(to or path), '\n')
    end
    if out.files       then push(out.files, to or path)    end
    if args.mut and to then civix.mv(path, to) end
    return
  end
  -- Search for patterns and substitution. If mut then write subs.
  local f, fpath; if args.mut and args.sub then
    fpath = (to or path)..'.SUB'; f = io.open(fpath, 'w')
  end
  local l = 1; for line in io.open(path, 'r'):lines() do
    local m, m2, patFound; for l, p in ipairs(pat) do -- find any matches
      m, m2 = line:find(p); if m then patFound = p; break end
    end; if not m then -- no match
      if f then f:write(line, '\n') end
      goto continue
    end
    if files then files = false -- =false -> pnt only once
      if log       then log:sty('path', pth.nice(path), '\n')   end
      if out.files then push(out.files, path)         end
    end
    line = (sub and line:gsub(patFound, sub)) or line
    if args.matches then
      if log         then
        local logl = line
        if sub and #line == 0 then logl = '<line removed>' end
        if pre then log:sty(nil, pre) end
        log:sty('meta', sfmt('% 6i: ', l))
        log:sty(nil, logl:sub(1, m-1))
        log:sty('match', logl:sub(m, m2))
        log:sty(nil, logl:sub(m2+1), '\n')
      end
      if out.matches then push(out.matches, line) end
    end
    if f and #line > 0 then f:write(line, '\n') end -- match
    ::continue:: l = l + 1
  end
  if f then -- close .SUB file and move it
    f:flush(); f:close()
    civix.mv(fpath, to or path)
    if to then civix.rm(path) end
  end
end

local function _defaultFn(path, ftype, args) if args.log then
  args.log:sty(nil, sfmt('?? Unknown ftype=%s: %s', ftype, path), '\n')
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
    assert(not args.fsub, 'cannot specify both sub and fsub')
  end
  if args.fsub then assert(
    args.fpat, 'must specify fpat with fsub'
  )end

  shim.bools(args, 'files', 'matches', 'dirs')
  args.depth = shim.number(args.depth or -1)
  args.dpat  = shim.list(args.dpat)
  args.excl  = shim.list(shim.excl, {'/%.[^/]+/'}, {})
  shim.short(args, 'd', 'dirs',  true)
  shim.short(args, 'm', 'mut',   true)
  shim.short(args, 'p', 'plain', true)
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
    args.log = Styler{
      f=args.log,
      color = shim.color(args.color, fd.isatty(args.log)),
    }
  end
  civix.walk(
    args, {
      file=function(path, _ftype)   return _fileFn(path, args, out)      end,
      dir =function(path, _ftype)   return _dirFn(path, args, out.dirs)  end,
      default=function(path, ftype) return _defaultFn(path, ftype, args) end,
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

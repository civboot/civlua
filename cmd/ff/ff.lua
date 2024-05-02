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
  ff -r --pat='OldTest([Cc]lass)' --sub='NewTesting%1 --mut

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

METATY_DOC = true
local pkg = require'pkg'
local shim = pkg'shim'
local mty = pkg'metaty'
local ds = pkg'ds'
local civix = pkg'civix'
local add = table.insert

local M = {}
M.FF = mty.doc[[
List arguments:
  path path2 path3 ...: list of paths to find/fix
]](mty.record2'FF') {
  [[depth[int]: depth to recurse (default=infinite)]],
  [[files[bool]: log/return files or substituted files.]],     files=true,
  [[matches[bool]: log/return the matches or substitutions.]], matches=true,
  [[dirs[bool]: log/return directories.]],                     dirs=false,
  [[fpat[string]: file name pattern to include.]],
  [[pat[table]: content pattern/s which searches inside of files
    and prints the results. Any match will include the file/line in
    the output in order. sub will use the first match found.]],
  [[dpat: directory name patterns to include, can specify multiple
    times.  ANY matches will include the directory.]],
  [[excl [table]: exclude pattern (default='/%.[^/]+/') 
    The default exclude ".hidden" directories.
    Can specify multiple times ANY matches will exclude the path]],
  [[mut [bool]: if true files may be modified. mut=false is like dry]],
    mut=false,
  [[fsub[string]: file substitute for fpat (rename files).
    Note: ff will never rename dirs.]],
  [[sub [string]: substitute pattern to go with pat (see lua's gsub)]],
  [[log: path or (Lua) filehandle to log to.]],
  [[fpre[string]: prefix characters before printing files]],        fpre='',
  [[dpre [string]: prefix characters before printing directories]], dpre='',
  [[plain [bool]: no line numbers]], plain=false,
}

-- FIXME
-- local f = mty.helpFmter(); mty.helpFields(M.FF, f)
-- M.DOC = DOC..'\n'..table.concat(f); f = nil; DOC = nil
M.DOC = DOC

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
    if args.log then wln(args.log, path, args.dpre) end
    if dirs then add(dirs, path) end
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
    if files and log   then wln(log, to or path, pre) end
    if out.files       then add(out.files, to or path) end
    if args.mut and to then civix.mv(path, to) end
    return
  end
  -- Search for patterns and substitution. If mut then write subs.
  local f, fpath; if args.mut and args.sub then
    fpath = (to or path)..'.SUB'; f = io.open(fpath, 'w')
  end
  local l = 1; for line in io.open(path, 'r'):lines() do
    local m, patFound; for l, p in ipairs(pat) do -- find any matches
      m = line:find(p); if m then patFound = p; break end
    end; if not m then -- no match
      if f then wln(f, line) end
      goto continue
    end
    if files then files = false -- =false -> pnt only once
      if log       then wln(log, path)       end
      if out.files then add(out.files, path) end
    end
    line = (sub and line:gsub(patFound, sub)) or line
    if args.matches then
      if log         then wln(log, line, pre, l) end
      if out.matches then add(out.matches, line) end
    end
    if f then wln(f, line) end
    ::continue:: l = l + 1
  end
  if f then -- close .SUB file and move it
    f:flush(); f:close()
    civix.mv(fpath, to or path)
    if to then civix.rm(path) end
  end
end

local function _defaultFn(path, ftype, args) if args.log then
  wln(args.log, sfmt('!! Unknown ftype=%s: %s', ftype, path))
end end

local function argPats(args)
  if args.F then return shim.list(args.pat) end
  local pat = {}; for i=#args,1,-1 do local a=args[i];
    if type(a) == 'string' and a:sub(1,1)=='%' then
      add(pat, a:sub(2)); table.remove(args, i)
    end
  end; return ds.extend(ds.reverse(pat), shim.list(args.pat))
end

function M.findfix(args, out, isExe)
  local argsTy = type(args); args = shim.parseStr(args, true)
  args.pat = argPats(args)
  if #args == 0 then add(args, '.') end
  if args.sub then
    assert(#args.pat, 'must specify pat with sub')
    assert(not args.fsub, 'cannot specify both sub and fsub')
  end
  if args.fsub then assert(
    args.fpat, 'must specify fpat with fsub'
  )end

  shim.bools(args, 'files', 'matches', 'dirs')
  args.depth = shim.number(args.depth or 1)
  args.dpat  = shim.list(args.dpat)
  args.excl  = shim.list(shim.excl, {'/%.[^/]+/'}, {})
  shim.short(args, 'd', 'dirs',  true)
  shim.short(args, 'r', 'depth', -1)
  shim.short(args, 'm', 'mut',   true)
  shim.short(args, 'p', 'plain', true)
  if args.depth < 0 then args.depth = nil end
  if type(args.log) == 'string' then args.log = io.open(args.log, 'a')
  elseif argsTy == 'string' and not args.log then args.log = io.stdout
  end

  if isExe then local ok;
    ok, args = pcall(M.FF, args)
    if not ok then io.stderr:write(args, '\n'); os.exit(1) end
  else args = M.FF(args) end

  -- args.dpre    = args.dpre or '\n'
  out = out or {
    files = args.files and {} or nil, dirs = args.dirs and {} or nil,
    matches = args.matches and {} or nil,
  }
  out.log = args.log
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

function M.exe(args, isExe)
  assert(isExe)
  if not args.depth   then args.depth = 1   end
  if args.depth == '' then args.depth = -1 end
  args.log = io.stdout
  M.findfix(args, {}, true)
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M

local DOC = [[ff: find+fix files
ff is a simple utility to find and fix files and file-content.

Examples (bash):
  ff path                   # print files at path (recursively)
  ff path --dir             # also print directories
  ff path --depth=3         # recurse to depth 3 (default=1)
  ff path --depth=          # recurse infinitely (depth=-1)
  ff path --depth=-1        # recurse infinitely (depth=-1)
  ff path --pat='my%s+name' # find Lua pattern like "my  name" in files at path
  ff path --pat='my%s+name' --matches=false  # print paths with match only
  ff path --pat='(name=)%S+' --sub='%1bob' # change name=anything to name=bob
  # add `--mut` to actually change the file contents
  ff path --fpat='%.txt'    # filter to .txt files
  ff path --fpat='(.*)%.txt' --fsub='%1.md'  # rename all .txt -> .md
  # rename OldTestClass -> NewTestClass, 'C' is not case sensitive.
  ff -r --pat='OldTest([Cc]lass)' --sub='NewTesting%1 --mut

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
]]

METATY_DOC = true
local mty = require'metaty'
local shim = require'shim'
local ds = require'ds'
local civix = require'civix'
local add = table.insert

local M = {}
M.FF = mty.doc[[
List arguments:
  path path2 path3 ...: list of paths to find/fix
]](mty.record'FF')
  :fieldMaybe('depth', 'number'):fdoc
    [[depth to recurse. '' or nil will recurse infinitely.]]
  :field('files', 'boolean', true):fdoc
    [[log/return files or substituted files.]]
  :field('matches', 'boolean', true):fdoc
    [[log/return the matches or substitutions.]]
  :field('dirs', 'boolean', false):fdoc[[log/return directories.]]
  :fieldMaybe('fpat', 'string'):fdoc
    [[file name pattern to include.]]
  :fieldMaybe('pat', 'string'):fdoc[[
content pattern which searches inside of files and prints the results.
    Also with for sub.]]
  :fieldMaybe('dpat', 'string'):fdoc[[
directory name patterns to include, can specify multiple times.
    ANY matches will include the directory.]]
  :fieldMaybe('excl', 'table'):fdoc[[
default='/%.[^/]+/', aka exclude hidden directories.
    directory name pattern/s to exclude, can specify multiple times.
    ANY matches will exclude the directory.]]
  :field('mut', 'boolean', false):fdoc[[
If not true will NEVER modify files (but does print)]]
  :fieldMaybe('fsub', 'string'):fdoc[[
file substitute for fpat (rename files).
    Note: ff will never rename dirs.]]
  :fieldMaybe('sub', 'string'):fdoc
    [[substitute pattern to go with pat (see lua's gsub)]]
  :fieldMaybe'log':fdoc[[path or (Lua) filehandle to log to.]]
  :field('fpre', 'string', ''):fdoc
    [[prefix characters before printing files]]
  :field('dpre', 'string', ''):fdoc
    [[prefix characters before printing directories]]
  :field('plain', 'boolean', false):fdoc'no line numbers'

local f = mty.helpFmter(); mty.helpFields(M.FF, f)
M.DOC = DOC..'\n'..f:toStr(); f = nil; DOC = nil

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
    end; if not include then
      print('!! excluded', path)
      return 'skip'
    end
  end
  if args.dirs then
    if args.log then wln(args.log, path, args.dpre) end
    if dirs then add(dirs, path) end
  end
end

local function _fileFn(path, args, out)
  for _, excl in ipairs(args.excl) do
    if path:find(excl) then return 'skip' end
  end
  local log, pre, files = args.log, args.fpre, args.files
  if args.fpat and not path:find(args.fpat) then return end
  if files and not args.pat then
    if log and not args.fsub then wln(log, path, pre) end
    if out.files then add(out.files, path) end
  end
  local to, text = nil, nil
  if args.fsub then to = path:gsub(args.fpat, args.fsub) end
  if to and files then files = false
    if log then wln(log, to, pre) end
    if to and out.mvfiles then add(out.mvfiles, to) end
  end

  local f, fpath; if args.mut and args.sub then
    fpath = (to or path)..'.SUB'; f = io.open(fpath, 'w')
  end

  local pat, sub = args.pat, args.sub;
  if not pat then
    if args.mut and to then civix.mv(path, to) end
    return
  end
  local l = 1; for line in io.open(path, 'r'):lines() do
    local m = line:find(pat); if not m then
      if f then wln(f, line) end
      goto continue
    end
    if files then files = false
      if log then wln(log, path) end
      if out.files then add(out.files, path) end
    end
    line = (sub and line:gsub(pat, sub)) or line
    if args.matches then
      if log then wln(log, line, pre, l) end
      if out.matches then add(out.matches, line) end
    end
    if f then wln(f, line) end
    ::continue::
    l = l + 1
  end
  if f then -- close file and move it
    f:flush(); f:close()
    civix.mv(fpath, to or path)
    if to then civix.rm(path) end
  end
end

function M.findfix(args, out, isExe)
  local argsTy = type(args); args = shim.parseStr(args, true)
  if #args == 0 then add(args, '.') end
  if args.sub then
    assert(args.pat, 'must specify pat with sub')
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
    args,
    function(path, depth) return _fileFn(path, args, out) end,
    function(path, depth) return _dirFn(path, args, out.dirs) end,
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

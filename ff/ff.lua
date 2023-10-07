local DOC = [[ff: find+fix files
ff is a simple utility to find and fix files and file-content.

Examples (bash):
  ff path                   # print files at path (recursively)
  ff path --dir             # also print directories
  ff path --depth=3         # recurse to depth 3 (default=1)
  ff path --depth=          # recurse infinitely (depth=nil)
  ff path --pat='my%s+name' # find Lua pattern like "my  name" in files at path
  ff path --pat='my%s+name' --matches=false  # print paths with match only
  ff path --pat='(name=)%S+' --sub='%1bob' # change name=anything to name=bob
  # add `--mut` to actually change the file contents
  ff path --fpat='%.txt'    # filter to .txt files
  ff path --fpat='(.*)%.txt' --fsub='%1.md'  # rename all .txt -> .md

Prints:
  In shell writes the file paths and possibly dir paths depending on files/dirs
  settings. In Lua writes nothing unless `log` is specified.

Returns (lua only):
  returns (files, dirs, matches) which may be nil depending on the files/dirs
  arguments.
]]

local mty = require'metaty'
local shim = require'shim'
local ds = require'ds'
local civix = require'civix'
local add = table.insert

local ff = mty.doc[[
List arguments:
  path path2 path3 ...: list of paths to find/fix
]](mty.record'findfix')
  :field('depth', 'number', 1):fdoc
    [[depth to recurse. '' or nil will recurse infinitely.]]
  :field('files', 'boolean', true):fdoc
    [[log/return files or substituted files.]]
  :field('matches', 'boolean', true):fdoc
    [[log/return the matches or substitutions.]]
  :field('dirs', 'boolean', false):fdoc[[log/return directories.]]
  :fieldMaybe('fpat', 'string'):fdoc[[
file name pattern to filter on, only files which match this pattern
will be included in the output and pattern search/substitute.]]
  :fieldMaybe('pat', 'string'):fdoc[[
content pattern which searches inside of files and prints the results.
Used for sub.]]
  :fieldMaybe('dpat', 'string'):fdoc
    [[name pattern to filter on]]
  :field('mut', 'boolean', false):fdoc[[
If not true will NEVER modify files (but does print)]]
  :fieldMaybe('fsub', 'string'):fdoc[[
file substitute for fpat (rename files).
Note: ff will never rename dirs.]]
  :fieldMaybe('sub', 'string'):fdoc
    [[substitute pattern to go with pat (see lua's gsub)]]
  :fieldMaybe'log':fdoc[[
In Lua this is the file handle to print results to.
In shell this is ignored (always io.stdout).]]
  :field('fpre', 'string', ''):fdoc
    [[prefix characters before printing files]]
  :field('dpre', 'string', '\n'):fdoc
    [[prefix characters before printing directories]]

local f = mty.helpFmter(); mty.helpFields(ff, f)
DOC = DOC..'\n'..f:toStr(); f = nil
local M = {DOC=DOC}

local function wln(f, msg, pre)
  if pre then f:write(pre) end; f:write(msg); f:write'\n'
end

local function _dirFn(path, args, dirs)
  if args.dpat and not path:find(args.dpat) then return 'skip' end
  if args.dirs then
    if args.log then wln(args.log, path, args.dpre) end
    if dirs then add(dirs, path) end
  end
end

local function _fileFn(path, args, out)
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
  for line in io.open(path, 'r'):lines() do
    local m = line:find(pat); if not m then
      if f then wln(f, line) end
      goto continue
    end
    if files then files = false
      if log then wln(log, path, pre) end
      if out.files then add(out.files, path) end
    end
    line = (sub and line:gsub(pat, sub)) or line
    if args.matches then
      if log then wln(log, line) end
      if out.matches then add(out.matches, line) end
     end
     if f then wln(f, line) end
    ::continue::
  end
  if f then -- close file and move it
    f:flush(); f:close()
    civix.mv(fpath, to or path)
    if to then civix.rm(path) end
  end
end

function M.findfix(args, out)
  if #args == 0 then add(args, '.') end
  if args.sub then
    assert(args.pat, 'must specify pat with sub')
    assert(not args.fsub, 'cannot specify both sub and fsub')
  end
  if args.fsub then assert(args.fpat, 'must specify fpat with fsub') end
  out = out or {
    files   = args.files   and {} or nil,
    dirs    = args.dirs    and {} or nil,
    matches = args.matches and {} or nil,
  }
  if args.depth ~= nil then args.depth = shim.number(args.depth or 1) end
  args.files   = shim.boolean(args.files   or true)
  args.matches = shim.boolean(args.matches or true)
  args.dirs    = shim.boolean(args.dirs)
  args.dpre    = args.dpre or '\n'

  civix.walk(
    args,
    function(path, depth) return _fileFn(path, args, out) end,
    function(path, depth) return _dirFn(path, args, out.dirs) end,
    args.depth
  )
  return out
end

function M.exe(args, isExe)
  assert(isExe)
  if args.depth == '' then args.depth = nil end
  args.log = io.stdout
  M.findfix(args, {})
end

M.shim = shim{help = DOC, exe = M.exe}

return M

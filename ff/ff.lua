local DOC = [[ff: find+fix files
ff is a simple utility to find and fix files and file-content.

It finds utilties within the given paths using the `pat` and `fpat` arguments,
which are standard lua patterns.  It fixes files by substituting values in
their name or contents using the `fsub` and `sub` arguments.  These follow
Lua's `string.find` and `string.gsub` conventions regarding patterns and group
matches.

List arguments:
  path path2 path3 ...: list of paths to find/fix

Key arguments:
  depth:   (default=1) depth to recurse. '' or nil will recurse infinitely.
  files:   (default=true) log/return files or substituted files
  matches: (default=true) log/return the matches or substitutions.
  dirs:    (default=false) log/return directories.

  fpat: file name pattern to filter on, only files which match this pattern
        will be included in the output and pattern search/substitute.
  pat: content pattern which searches inside of files and prints the results.
       Used for sub.
  dpat: dir name pattern to filter on

  mut: boolean. If not true will NEVER modify files (but does print)
  fsub: file substitute for fpat (rename files). ff will never rename dirs.
  sub: substitute pattern to go with pat (see lua's gsub)
  log: In Lua this is the file handle to print results to.
       In shell this is ignored (always io.stdout)

Prints:
  In shell writes the file paths and possibly dir paths depending on files/dirs
  settings. In Lua writes nothing unless `log` is specified.

Returns (lua only):
  returns (files, dirs, matches) which may be nil depending on the files/dirs
  arguments.
]]
local M = {DOC=DOC}

local shim = require'shim'
local mty = require'metaty'
local ds = require'ds'
local civix = require'civix'
local add = table.insert

local function wln(f, msg) f:write(msg); f:write'\n' end

local function _dirFn(path, args, dirs)
  if args.dpat and not path:find(args.dpat) then return 'skip' end
  if args.dirs then
    if args.log then args.log:write'\n'; wln(args.log, path) end
    if dirs then add(dirs, path) end
  end
end

local function _fileFn(path, args, out)
  local log = args.log
  if args.fpat and not path:find(args.fpat) then return end
  if args.files then
    if log and not args.fsub then wln(log, path) end
    if out.files then add(out.files, path) end
  end
  local to, text = nil, nil
  if args.fsub then to = path:gsub(args.fpat, args.fsub) end
  if to and args.files then
    if log then wln(log, to) end
    if to and out.mvfiles then add(out.mvfiles, to) end
  end

  local f, fpath; if args.mut and args.sub then
    fpath = (to or path)..'.SUB'; f = io.open(fpath, 'w')
  end

  local pat, sub = args.pat, args.sub; if not pat then return end
  for line in io.open(path, 'r'):lines() do
    local m = line:find(pat); if not m then
      if f then wln(f, line) end
      goto continue
    end
    line = (sub and line:gsub(pat, sub)) or sub
    if args.matches then
      if log then wl(log, line) end
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
  out = out or {
    files   = args.files   and {} or nil,
    dirs    = args.dirs    and {} or nil,
    matches = args.matches and {} or nil,
  }
  args.depth = shim.number(args.depth or 1)
  shim.default(args, 'files', true)
  shim.default(args, 'matches', true)
  if args.files == nil then args.files = true end

  civix.walk(
    args,
    function(path, depth) return _fileFn(path, args, out) end,
    function(path, depth) return _dirFn(path, args, out.dirs) end
  )
  return out
end

function M.exe(args, isExe)
  assert(isExe)
  args.log = io.stdout
  M.findfix(args, {})
end

shim{help = DOC, exe = M.exe}

return M

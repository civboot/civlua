local G = G or _G

--- Simple logging library, set i.e. LOGLEVEL=TRACE to enable logging.
---
--- This module has the functions [$trace info warn err crit] with the signature:
--- [$function(fmt, ... [, data])] [+
--- * the ... are the format args which behave like [$fmt.format] (aka [$%q]
---   formats tables/etc).
--- * data is optional arbitrary data that can be serialized/formatted.
--- ]
---
--- To enable logging the user should set a global (or env var) LOGLEVEL
--- to oneof: C/CRIT/1 E/ERROR/2 W/WARN/3 I/INFO/4 T/TRACE/5
---
--- This module also sets (if not already set) the global LOGFN to [$ds.logFn]
--- which logs to stderr. This fn is called with signature
--- [$function(level, srcloc, fmt, ...)]
local M = G.mod and G.mod'ds.log' or {}
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'

local push, concat, sfmt = table.insert, table.concat, string.format
local Fmt = fmt.Fmt
local io = io

M.time = function() return os.date():match'%d%d:%d%d:%d%d' end

local LEVEL = ds.Checked{
  SLIENT=0, [0]='SILENT',
  C=1, CRIT=1,
  E=2, ERROR=2,
  W=3, WARN=3,
  I=4, INFO=4,
  T=5, TRACE=5,
  'CRIT', 'ERROR', 'WARN', 'INFO', 'TRACE'
}; M.LEVEL = LEVEL
local SHORT = ds.Checked{'C', 'E', 'W', 'I', 'T'}
function M.levelInt(lvl)
  local lvl = tonumber(lvl) or M.LEVEL[lvl]
  return M.LEVEL[lvl] and lvl or error('invalid lvl: '..tostring(lvl))
end
function M.levelStr(lvl) return M.LEVEL[M.levelInt(lvl)] end

--- set the global logging level (default=os.getenv'LOGLEVEL')
M.setLevel = function(lvl)
  G.LOGLEVEL = M.levelInt(lvl or os.getenv'LOGLEVEL' or 0)
end
M.setLevel(G.LOGLEVEL)

function M.logFn(lvl, loc, fmt, ...)
  if LOGLEVEL < lvl then return end
  local f, lasti, i, args, nargs = io.fmt, 1, 0, {...}, select('#', ...)
  push(f, sfmt('%s %s %s: ', SHORT[lvl], M.time(), loc)); f:flush()
  f:level(1)
  local nargs, i = select('#', ...), f:format(fmt, ...)
  if i == (nargs - 1) then push(f, ' '); f(args[i + 1]) -- data
  elseif i ~= nargs then error('invalid #args: '..nargs..' %fmts='..i) end
  f:level(-1); f:write'\n'; f:flush()
end
G.LOGFN = G.LOGFN or M.logFn

local function _log(lvl, fmt, ...)
  LOGFN(lvl, ds.shortloc(2), fmt, ...)
end

function M.crit(...)  if LOGLEVEL >= 1 then _log(1, ...) end end
function M.err(...)   if LOGLEVEL >= 2 then _log(2, ...) end end
function M.warn(...)  if LOGLEVEL >= 3 then _log(3, ...) end end
function M.info(...)  if LOGLEVEL >= 4 then _log(4, ...) end end
function M.trace(...) if LOGLEVEL >= 5 then _log(5, ...) end end

--- used in tests
M.LogTable = mty.record'LogTable'{}
M.LogTable.__call = function(lt, ...) push(lt, {...}) end

return M

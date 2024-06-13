-- Simple logging library.
--
-- This module has the functions {trace info warn err crit} with the signature:
-- function(fmt, ... [, data])
-- * the ... are the format args which behave like metaty.format (aka %q
--   formats tables/etc).
-- * data is optional arbitrary data that can be serialized/formatted.
--
-- To enable logging the user should set a global (or env var) LOGLEVEL
-- to oneof: C/CRIT/1 E/ERROR/2 W/WARN/3 I/INFO/4 T/TRACE/5
--
-- This module also sets (if not already set) the global LOGFN to ds.logFn
-- which logs to stderr. This fn is called with signature
-- function(level, srcloc, message, data)
local M = mod and mod'ds.log' or {}
local mty = require'metaty'
local ds = require'ds'
local push, sfmt = table.insert, string.format

M.time = function() return os.date():match'%d%d:%d%d:%d%d' end

M.LEVELS = {
  SLIENT=0, [0]='SILENT',
  C=1, CRIT=1,
  E=2, ERROR=2,
  W=3, WARN=3,
  I=4, INFO=4,
  T=5, TRACE=5,
  'CRIT', 'ERROR', 'WARN', 'INFO', 'TRACE'
}
M.SHORT = {'C', 'E', 'W', 'I', 'T'}
function M.levelInt(lvl)
  local lvl = tonumber(lvl) or M.LEVELS[lvl]
  return M.LEVELS[lvl] and lvl or error('invalid lvl: '..tostring(lvl))
end
function M.levelStr(lvl) return M.LEVELS[M.levelInt(lvl)] end
-- set the global logging level (default=os.getenv'LOGLEVEL')
function M.setLevel(lvl)
  _G.LOGLEVEL = M.levelInt(lvl or os.getenv'LOGLEVEL' or 0)
end
M.setLevel(LOGLEVEL)

function M.logFn(lvl, loc, msg, data)
  if LOGLEVEL < lvl then return end
  local f = mty.Fmt:pretty{sfmt('%s %s %s: %s',
     M.SHORT[lvl], M.time(), loc, msg
  )}
  if data then push(f, ' '); f(data) end
  push(f, '\n')
  io.stderr:write(table.concat(f))
end
LOGFN = LOGFN or M.logFn -- GLOBAL

local function logfmt(fmt, ...) --> string, data?
  local i, args, nargs = 0, {...}, select('#', ...)
  local Fmt, tc = mty.Fmt, table.concat
  local msg = fmt:gsub('%%.', function(m)
    if m == '%%' then return '%' end
    i = i + 1
    return m ~= '%q' and sfmt(m, args[i])
      or tc(Fmt{}(args[i]))
  end)
  if (i ~= nargs) and (i ~= nargs - 1) then error(
    'invalid #args: '..nargs..' %fmts='..i
  )end
  return msg, args[i + 1]
end
M.logfmt = logfmt

local function _log(lvl, fmt, ...)
  LOGFN(lvl, ds.shortloc(2), logfmt(fmt, ...))
end

function M.crit(...)  if LOGLEVEL >= 1 then _log(1, ...) end end
function M.err(...)   if LOGLEVEL >= 2 then _log(2, ...) end end
function M.warn(...)  if LOGLEVEL >= 3 then _log(3, ...) end end
function M.info(...)  if LOGLEVEL >= 4 then _log(4, ...) end end
function M.trace(...) if LOGLEVEL >= 5 then _log(5, ...) end end

-- Log to a table. This is typically used for in tests/etc
M.LogTable = mty.record'LogTable'{}
M.LogTable.__call = function(lc, ...)
  local msg, data = logfmt(...)
  push(lc, {msg, data=data})
end

return M

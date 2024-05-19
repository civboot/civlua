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

M.levelMap = {
  SLIENT=0, [0]='SILENT',
  C=1, CRIT=1,
  E=2, ERROR=2,
  W=3, WARN=3,
  I=4, INFO=4,
  T=5, TRACE=5,
  'CRIT', 'ERROR', 'WARN', 'INFO', 'TRACE'
}
function M.levelInt(lvl)
  local lvl = tonumber(lvl) or M.levelMap[lvl]
  -- assert level is valid
  return M.levelMap[lvl] and lvl or error('invalid lvl: '..tostring(lvl))
end
function M.levelStr(lvl) return M.levelMap[M.levelInt(lvl)] end
function M.setLevel(lvl) _G.LOGLEVEL = M.levelInt(lvl) end -- GLOBAL
M.setLevel(LOGLEVEL or os.getenv'LOGLEVEL' or 0)

function M.logFn(lvl, loc, msg, data)
  local f = mty.Fmt:pretty{sfmt('%s %s %s: %s',
     lvl, M.time(), loc, msg
  )}
  if data then push(f, ' '); f(data) end
  push(f, '\n')
  io.stderr:write(table.concat(f))
end
LOGFN = LOGFN or M.logFn -- GLOBAL

local function _log(lvl, fmt, ...)
  local i, args, tc = 0, {...}, table.concat
  local msg = fmt:gsub('%%.', function(m)
    if m == '%%' then return '%' end
    i = i + 1
    return m ~= '%q' and sfmt(m, args[i])
      or tc(mty.Fmt{}(args[i]))
  end)
  assert((i == #args) or (i == #args - 1), 'invalid #args')
  LOGFN(lvl, ds.shortloc(2), msg, args[i + 1])
end

function M.crit(...)  if LOGLEVEL >= 1 then _log('C', ...) end end
function M.err(...)   if LOGLEVEL >= 2 then _log('E', ...) end end
function M.warn(...)  if LOGLEVEL >= 3 then _log('W', ...) end end
function M.info(...)  if LOGLEVEL >= 4 then _log('I', ...) end end
function M.trace(...) if LOGLEVEL >= 5 then _log('T', ...) end end

return M

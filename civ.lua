#!/usr/bin/lua
mod = mod or require'pkg'.mod

-- civ module: packaged dev environment
local M = mod'civ'

CWD = false
DOC,          METATY_CHECK  = false, false
LOGLEVEL,     LOGFN         = false, false
LAP_READY,    LAP_ASYNC     = false, false
LAP_FNS_SYNC, LAP_FNS_ASYNC = false, false
LAP_CORS,     LAP_TRACE     = false, false

local initG = {}; for k in pairs(_G) do initG[k] = true end

local shim    = require'shim'
local mty     = require'metaty'
local civtest = require'civtest'
local ds      = require'ds'
local pth     = require'ds.path'
local fd      = require'fd'

local doc   = require'doc'
local ff    = require'ff'
local ele   = require'ele'
local rock  = require'pkgrock'
local astyle = require'asciicolor.style'
civtest.assertGlobals(initG)

local sfmt = string.format


M.HELP = [[help module.any.object
Get help for any lua module (including ones in civlib)]]

-- style lua value
local function styleValue(st, v)
  if type(v) == 'function' then
    local name, loc = mty.fninfo(v)
    st:styled('meta', "fn'")
    st:styled('call', name)
    st:styled('meta', "'")
    if loc then
      st:styled('path', pth.nice(loc))
    end
  else st:styled('literal', mty.tostring(v)) end
end
local function styleDocItem(st, di)
  st:styled('var',  sfmt('%-16s', di.name or '?'))
  st:styled('type', sfmt('%-20s', di:typeStr()))
  if di.default ~= nil then
    st:write' '; st:styled('meta', '=', ' ')
    styleValue(st, di.default)
  end
  if di.path then st:styled('path', pth.nice(di.path)) end
  if di.doc and di.doc ~= '' then
    st:incIndent(); st:write'\n'
    st:styled(nil, di.doc) -- TODO: style cxt
    st:decIndent()
  end
end

local function styleDocItems(st, items, name)
  st:write'\n' st:incIndent()
  st:styled('meta', name, '\n')
  for i, di in ipairs(items) do
    styleDocItem(st, di); if i < #items then st:write'\n' end
  end
  st:decIndent()
end

local function getHelp(args)
  if not shim.color(args.color, fd.isatty(io.stdout)) then
    return print(doc(args[1]))
  end

  -- local style = require'asciicolor.style'.loadStyle()
  local d = doc.find(args[1])
  local st = astyle.Styler()
  if not d then
    return st:styled('error', sfmt('could not find %s', args[1]))
  end
  st:styled('api',  d.name, ' ')
  st:styled('meta', '[');
  st:styled('type', d.ty or '?')
  st:styled('meta', ']', ' ')
  st:styled('path', pth.nice(d.path or '?/?'))
  st:incIndent(); st:write'\n'
  for i, l in ipairs(d.comments or {}) do
    -- TODO: style cxt
    st:styled(nil, l)
    if i < #d.comments then st:write'\n' end
  end
  st:decIndent(); st:write'\n'

  if d.fields and next(d.fields) then
    styleDocItems(st, d.fields, 'Fields')
    st:write'\n'
  end
  if d.other and next(d.other) then
    styleDocItems(st, d.other, 'Methods, Etc')
    st:write'\n'
  end
end

M.help = function(args, isExe)
  if #args == 0 then print(M.HELP) return end
  local ok, err = ds.try(function() getHelp(args) end)
  if not ok then
    mty.print(string.format('Error %s:', args[0]), err)
  end
end

shim {
  help=DOC,
  subs = {
    help = {help=M.HELP, exe=M.help},
    ele  = ele,
    ff   = ff.shim,
    rock = rock.shim,
    ['cxt.html'] = require'cxt.html'.shim,
  },
}

return M

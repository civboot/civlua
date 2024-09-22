#!/usr/bin/env -S lua -e "require'pkglib'()"
--- module documentation
local M = mod and mod'helloworld' or setmetatable({}, {}) -- see lib/pkg
MAIN = MAIN or M -- must be before imports

local shim = require'shim'
local mty  = require'metaty'
local fmt  = require'fmt'
local fd  = require'fd'
local doc = require'doc'
local style = require'asciicolor.style'

--- Write message to screen with any style.
---
--- List args are concatenated as the message, or [$"Hello world!"] is used
M.Args = mty'Args' {
  'style [string]: style to use', style='h2',
  'to [string]: where to print to (default=stdout)',
  'color [string]: whether to use color [$true|false|always|never]',
}

M.main = function(args)
  local args = M.Args(shim.parseStr(args))
  local styler = style.Styler:default(args.to, args.color)
  fmt.assertf(style.dark[args.style],
              'Error: %s is not a valid style', args.style)
  if args.help then return require'doc'.styleHelp(styler, M.Args) end
  local msg = table.concat(args, ' ')
  if #msg == 0 then msg = 'Hello world!' end
  styler:styled(args.style, msg, '\n')
  return styler
end

-- check if this is the top level script and execute if not.
-- note: arg is a default lua global
if M == MAIN then M.main(shim.parse(arg)) os.exit(0) end
return M -- can also use as a library

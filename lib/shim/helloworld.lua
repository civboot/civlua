#!/usr/bin/env -S lua -e "require'pkglib'()"
--- module documentation
local M = mod and mod'helloworld' or setmetatable({}, {}) -- see lib/pkg
MAIN = MAIN or M -- must be before imports
local shim = require'shim'
local mty  = require'metaty'
local fd  = require'fd'
local style = require'asciicolor.style'

--- Write message to screen with any style.
---
--- List args are concatenated as the message, or [$"Hello world!"] is used
M.Main = mty'Main' {
  'style [string]: style to use', style='h2',
  'to [string]: where to print to (default=stdout)',
  'color [string]: whether to use color [$true|false|always|never]',
}

M.main = function(args)
  args = M.Main(shim.parse(args))
  mty.assertf(style.dark[args.style], 'Error: %s is not a valid style', args.style)
  local to = shim.file(args.to, io.stdout)
  local styler = style.Styler{
    f = to, color = shim.color(args.color, fd.isatty(to)),
  }
  if shim.checkHelp(args, to, styler.color) then return end

  local msg = table.concat(args, ' ')
  if #msg == 0 then msg = 'Hello world!' end
  styler:styled(args.style, msg, '\n')
  return styler
end

-- if this is the top-level lua script that sets MAIN
-- then run main and exit.
if M == MAIN then
  M.main(arg) -- note: arg is the default global from the command line
  os.exit(0)
end

return M -- can also use as a library

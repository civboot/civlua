local pkg = require'pkglib'
local mty = require'metaty'
local gap  = require'rebuf.gap'

local M = {Gap=gap.Gap}

M.Chain = mty'Chain'{}
M.Chain.__newindex = nil
getmetatable(M.Chain).__index = nil
getmetatable(M.Chain).__call = mty.constructUnchecked

M.ViewId = 0
M.nextViewId   = function() M.ViewId   = M.ViewId   + 1; return M.ViewId   end

-- Window container
-- Note: Window also acts as a list for it's children
M.Window = mty'Window' {
  'id[int]',
  'container', -- parent (Window/Model)
  'splitkind[string]', -- nil, h, v
  'tl[int]',  'tc[int]', -- term lines, cols
  'th[int]',  'tw[int]', -- term height, width
}

M.Edit = mty'Edit' {
  'id[int]',
  'container', -- parent (Window/Model)
  'canvas',
  'buf[Buffer]',
  'l[int]',     'c[int]', -- cursor line, col
  'vl[int]',    'vc[int]', -- view   line, col (top-left)
  'tl[int]',    'tc[int]', -- term   line, col (top-left)
  'th[int]',    'tw[int]', -- term   height, width
  'fh[int]',    'fw[int]', -- force h,w
}
M.Edit.fh = 0; M.Edit.fw = 0

M.Action = mty'Action' {
  'name[string]', 'fn[function]',
  'brief[string]',
  'doc[string]',
  'config',       'data' -- action specific
}

-- Bindings to Actions
M.Bindings = mty'Bindings' {
  'insert', 'command',
}

M.Model = mty'Model' {
  'mode[string]',
  'h[int]',  'w[int]',  -- window height/width
  'view', -- Edit or Cols or Rows
  'edit', -- The active editor
  'statusEdit',      'searchEdit',
  'buffers[int]',  'freeBufId[int]',  'freeBufIds',
  'start[Epoch]',  'lastDraw[Epoch]',
  'bindings[Bindings]',
  'chain',
  'inputCo',  'term',
}

return M

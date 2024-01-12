local pkg = require'pkg'
local mty = pkg'metaty'
local gap  = pkg'rebuf.gap'

local record = mty.record

local M = {Gap=gap.Gap}

local NUM = 'number'

M.Chain = mty.rawTy'Chain'

M.ViewId = 0
M.nextViewId   = function() M.ViewId   = M.ViewId   + 1; return M.ViewId   end

-- Window container
-- Note: Window also acts as a list for it's children
M.Window = record'Window'
  :field('id', NUM)
  :fieldMaybe'container' -- parent (Window/Model)
  :fieldMaybe('splitkind', 'string') -- nil, h, v
  :field('tl', NUM)  :field('tc', NUM) -- term lines, cols
  :field('th', NUM)  :field('tw', NUM) -- term height, width

M.Edit = record'Edit'
  :field('id', NUM)
  :fieldMaybe'container' -- parent (Window/Model)
  :fieldMaybe'canvas'
  :field('buf', Buffer)
  :field('l',  NUM)    :field('c',  NUM) -- cursor line, col
  :field('vl', NUM)    :field('vc', NUM) -- view   line, col (top-left)
  :field('tl', NUM)    :field('tc', NUM) -- term   line, col (top-left)
  :field('th', NUM)    :field('tw', NUM) -- term   height, width
  :field('fh', NUM, 0) :field('fw', NUM, 0) -- force h,w

M.Action = record'Action'
  :field('name', 'string') :field('fn', 'function')
  :fieldMaybe('brief', 'string')
  :fieldMaybe('doc', 'string')
  :fieldMaybe'config'  :fieldMaybe'data' -- action specific

-- Bindings to Actions
M.Bindings = record'Bindings'
  :field'insert'
  :field'command'

M.Model = record'Model'
  :field('mode', 'string')
  :field('h', NUM)  :field('w', NUM)  -- window height/width
  :field'view' -- Edit or Cols or Rows
  :field'edit' -- The active editor
  :field'statusEdit'      :field'searchEdit'
  :field('buffers', Map)  :field('freeBufId', NUM)  :field'freeBufIds'
  :field('start', Epoch)  :field('lastDraw', Epoch)
  :field('bindings', Bindings)
  :fieldMaybe'chain'
  :field'inputCo'  :field'term'

return M

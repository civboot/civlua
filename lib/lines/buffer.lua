local mty = require'metaty'
local ds = require'ds'
local lines = require'lines'
local motion  = require'lines.motion'
local Gap  = require'lines.Gap'
local log = require'ds.log'

local M = {}
local span, bound = lines.span, lines.bound
local push, ty = table.insert, mty.ty
local concat = table.concat

M.ChangeId = 0
M.nextChangeId = function() M.ChangeId = M.ChangeId + 1; return M.ChangeId end

M.ChangeStart = mty'ChangeStart' {
  'l1[int]',       'c1[int]',
  'l2[int]',       'c2[int]',
}

M.Change = mty'Change' {
  'k[string]', 's[string]',
  'l[int]',    'c[int]',
}

M.Buffer = mty'Buffer' {
  'id  [int]', 'name [str?]',
  'dat [Gap]',
  'readonly [bool]', -- TODO: actually implement readonly
  'l [int]', 'c [int]', -- used by clients

  -- recorded changes from update (for undo/redo)
  'changes',
  'changeMax [int]',    changeMax=0,
  'changeStartI [int]', changeStartI=0,
  'changeI [int]',      changeI=0,

  'tmp[parents]: if set, delete when parents are empty',
  'ext[table]: table for arbitrary extensions',
}

getmetatable(M.Buffer).__index = mty.hardIndex
M.Buffer.__newindex            = mty.hardNewindex

getmetatable(M.Buffer).__call = function(T, t)
  assert(t.dat, 'must set dat')
  if #t.dat == 0 then push(t.dat, '') end
  t.changes = t.changes or {}
  t.ext = t.ext or {}
  return mty.construct(T, t)
end

local Buffer, Change, ChangeStart = M.Buffer, M.Change, M.ChangeStart

local function redoRm(ch, b)
  local len = #ch.s - 1; if len < 0 then return ch end
  local dat = b.dat
  local l2, c2 = lines.offset(dat, len, ch.l, ch.c)
  lines.remove(dat, ch.l, ch.c, l2, c2)
  return ch
end

local function redoIns(ch, b)
  lines.inset(b.dat, ch.s, ch.l, ch.c)
  return ch
end

local CHANGE_REDO = { ins=redoIns, rm=redoRm, }
local CHANGE_UNDO = { ins=redoRm, rm=redoIns, }

-- TODO: remove this
Buffer.new = function(s)
  return Buffer{ dat=Gap(s) }
end

Buffer.path = function(b) return b.dat.path end --> path?

Buffer.__fmt = function(b, fmt)
  fmt:write(('Buffer{%s, id=%s, path=%q}'):format(
    b.tmp and (#b.tmp == 0) and '(closed) ' or '(tmp)',
    b.id, b.dat.path))
end
Buffer.__len = function(b)    return #b.dat end
Buffer.get   = function(b, i) return b.dat:get(i) end

Buffer.addChange = function(b, ch)
  b.changeI = b.changeI + 1; b.changeMax = b.changeI
  b.changes[b.changeI] = ch
  return ch
end
--- Return true if anything has changed since i (default=changeStartI)
Buffer.changed = function(b, i) --> bool
  return (i or b.changeStartI) < b.changeI
end
Buffer.discardUnusedStart = function(b)
  if b.changeI ~= 0 and b.changeStartI == b.changeI then
    local ch = b.changes[b.changeI]
    assert(ty(ch) == ChangeStart)
    b.changeI = b.changeI - 1
    b.changeMax = b.changeI
    b.changeStartI = 0
  end
end
Buffer.changeStart = function(b, l, c)
  local ch = ChangeStart{l1=l, c1=c}
  b:discardUnusedStart()
  b:addChange(ch); b.changeStartI = b.changeI
  return ch
end
Buffer.getStart = function(b)
  if b.changeStartI <= b.changeMax then
    return b.changes[b.changeStartI]
  end
end
Buffer.printChanges = function(b)
  for i=1,b.changeMax do
    pnt(b.changes[i], (i == b.changeI) and "<-- changeI" or "")
  end
end

Buffer.changeIns = function(b, s, l, c)
  return b:addChange(Change{k='ins', s=s, l=l, c=c})
end
Buffer.changeRm = function(b, s, l, c)
  return b:addChange(Change{k='rm', s=s, l=l, c=c})
end

Buffer.canUndo = function(b) return b.changeI >= 1 end
-- TODO: shouldn't it be '<=' ?
Buffer.canRedo = function(b) return b.changeI < b.changeMax end

Buffer.undoTop = function(b)
  if b:canUndo() then return b.changes[b.changeI] end
end
Buffer.redoTop = function(b)
  if b:canRedo() then return b.changes[b.changeI + 1] end
end

Buffer.undo = function(b)
  local ch = b:undoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0

  local done = {}
  while ch do
    b.changeI = b.changeI - 1
    push(done, ch)
    if ty(ch) == ChangeStart then break
    else
      assert(ty(ch) == Change)
      CHANGE_UNDO[ch.k](ch, b)
    end
    ch = b:undoTop()
  end
  return ds.reverse(done)
end

Buffer.redo = function(b)
  local ch = b:redoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0
  assert(ty(ch) == ChangeStart)
  local done = {ch}; b.changeI = b.changeI + 1
  ch = b:redoTop(); assert(ty(ch) ~= ChangeStart)
  while ch and ty(ch) ~= ChangeStart do
    b.changeI = b.changeI + 1
    push(done, ch)
    CHANGE_REDO[ch.k](ch, b)
    ch = b:redoTop()
  end
  return done
end

--- Some APIs allow negative values for spans, this converts them
--- to absolute positive line/cols.
Buffer.span = function(b, ...)
  local l, c, l2, c2 = span(...)
  if l  < 0 then l  = #b + l  + 1 end
  if l2 < 0 then l2 = #b + l2 + 1 end
  if c  and c  < 0 then c  = #b:get(l)  + c  + 1 end
  if c2 and c2 < 0 then c2 = #b:get(l2) + c2 + 1 end
  return l, c, l2, c2
end

Buffer.append = function(b, s)
  local ch = b:changeIns(s, #b.dat + 1, 1)
  b.dat:append(s)
  return ch
end

Buffer.insetTracked = function(b, l, lines, rmlen) --> changes
  local chs, rm = {}, b:inset(l, lines, rmlen)
  if rm then
    push(chs, b:changeRm(concat(rm, '\n'), l,1))
  end
  if lines and #lines > 0 then
    push(chs, b:changeIns(concat(lines, '\n'), l,1))
  end
  return chs
end

Buffer.insert = function(b, s, l, c)
  l, c = lines.bound(b.dat, l, c)
  local ch = b:changeIns(s, l, c)
  lines.inset(b.dat, s, l, c)
  return ch
end

Buffer.remove = function(b, ...)
  local l, c, l2, c2 = span(...)
  local dat = b.dat
  l,c = bound(dat, l,c); l2,c2 = bound(dat, l2,c2)
  local lt, ct = motion.topLeft(l, c, l2, c2)
  lt, ct = lines.bound(dat, lt, ct)
  local ch = lines.sub(dat, l, c, l2, c2)
  ch = (type(ch)=='string' and ch) or concat(ch, '\n')
  ch = b:changeRm(ch, lt, ct)
  log.info('remove %s.%s : %s.%s', l, c, l2, c2)
  lines.remove(dat, l, c, l2, c2)
  return ch
end

ChangeStart.__tostring = function(c)
  return string.format('[%s.%s -> %s.%s]', c.l1, c.c1, c.l2, c.c2)
end
Change.__tostring = function(c)
  return string.format('{%s %s.%s %q}', c.k, c.l, c.c, c.s)
end

return M

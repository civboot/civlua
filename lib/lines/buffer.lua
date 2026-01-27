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
function M.nextChangeId() M.ChangeId = M.ChangeId + 1; return M.ChangeId end

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
  lines.insert(b.dat, ch.s, ch.l, ch.c)
  return ch
end

local CHANGE_REDO = { ins=redoIns, rm=redoRm, }
local CHANGE_UNDO = { ins=redoRm, rm=redoIns, }

-- TODO: remove this
function Buffer.new(s)
  return Buffer{ dat=Gap(s) }
end

function Buffer:path() return self.dat.path end --> path?

function Buffer:__fmt(fmt)
  fmt:write(('Buffer{%s, id=%s, path=%q}'):format(
    self.tmp and (#self.tmp == 0) and '(closed) ' or '(tmp)',
    self.id, self.dat.path))
end
function Buffer:__len() return #self.dat       end
function Buffer:get(i)  return self.dat:get(i) end

function Buffer:addChange(ch)
  self.changeI = self.changeI + 1; self.changeMax = self.changeI
  self.changes[self.changeI] = ch
  return ch
end
--- Return true if anything has changed since i (default=changeStartI)
function Buffer:changed(i) --> bool
  return (i or self.changeStartI) < self.changeI
end
function Buffer:discardUnusedStart()
  if self.changeI ~= 0 and self.changeStartI == self.changeI then
    local ch = self.changes[self.changeI]
    assert(ty(ch) == ChangeStart)
    self.changeI = self.changeI - 1
    self.changeMax = self.changeI
    self.changeStartI = 0
  end
end
function Buffer:changeStart(l, c)
  local ch = ChangeStart{l1=l, c1=c}
  self:discardUnusedStart()
  self:addChange(ch); self.changeStartI = self.changeI
  return ch
end
function Buffer:getStart()
  if self.changeStartI <= self.changeMax then
    return self.changes[self.changeStartI]
  end
end
function Buffer:printChanges()
  for i=1,self.changeMax do
    pnt(self.changes[i], (i == self.changeI) and "<-- changeI" or "")
  end
end

function Buffer:changeIns(s, l, c)
  return self:addChange(Change{k='ins', s=s, l=l, c=c})
end
function Buffer:changeRm(s, l, c)
  return self:addChange(Change{k='rm', s=s, l=l, c=c})
end

function Buffer:canUndo() return self.changeI >= 1 end
-- TODO: shouldn't it be '<=' ?
function Buffer:canRedo() return self.changeI < self.changeMax end

function Buffer:undoTop()
  if self:canUndo() then return self.changes[self.changeI] end
end
function Buffer:redoTop()
  if self:canRedo() then return self.changes[self.changeI + 1] end
end

function Buffer:undo()
  local ch = self:undoTop(); if not ch then return end
  self:discardUnusedStart(); self.changeStartI = 0

  local done = {}
  while ch do
    self.changeI = self.changeI - 1
    push(done, ch)
    if ty(ch) == ChangeStart then break
    else
      assert(ty(ch) == Change)
      CHANGE_UNDO[ch.k](ch, self)
    end
    ch = self:undoTop()
  end
  return ds.reverse(done)
end

function Buffer:redo()
  local ch = self:redoTop(); if not ch then return end
  self:discardUnusedStart(); self.changeStartI = 0
  assert(ty(ch) == ChangeStart)
  local done = {ch}; self.changeI = self.changeI + 1
  ch = self:redoTop(); assert(ty(ch) ~= ChangeStart)
  while ch and ty(ch) ~= ChangeStart do
    self.changeI = self.changeI + 1
    push(done, ch)
    CHANGE_REDO[ch.k](ch, self)
    ch = self:redoTop()
  end
  return done
end

--- Some APIs allow negative values for spans, this converts them
--- to absolute positive line/cols.
function Buffer:span(...)
  local l, c, l2, c2 = span(...)
  if l  < 0 then l  = #self + l  + 1 end
  if l2 < 0 then l2 = #self + l2 + 1 end
  if c  and c  < 0 then c  = #self:get(l)  + c  + 1 end
  if c2 and c2 < 0 then c2 = #self:get(l2) + c2 + 1 end
  return l, c, l2, c2
end

function Buffer:append(s)
  local ch = self:changeIns(s, #self.dat + 1, 1)
  self.dat:append(s)
  return ch
end

function Buffer:insetTracked(l, lines, rmlen) --> changes
  local chs, rm = {}, self:inset(l, lines, rmlen)
  if rm then
    push(chs, self:changeRm(concat(rm, '\n'), l,1))
  end
  if lines and #lines > 0 then
    push(chs, self:changeIns(concat(lines, '\n'), l,1))
  end
  return chs
end

function Buffer:insert(s, l, c)
  l, c = lines.bound(self.dat, l, c)
  local ch = self:changeIns(s, l, c)
  lines.insert(self.dat, s, l, c)
  return ch
end

function Buffer:remove(...)
  local l, c, l2, c2 = span(...)
  local dat = self.dat
  l,c = bound(dat, l,c); l2,c2 = bound(dat, l2,c2)
  local lt, ct = motion.topLeft(l, c, l2, c2)
  lt, ct = lines.bound(dat, lt, ct)
  local ch = lines.sub(dat, l, c, l2, c2)
  ch = (type(ch)=='string' and ch) or concat(ch, '\n')
  ch = self:changeRm(ch, lt, ct)
  log.info('remove %s.%s : %s.%s', l, c, l2, c2)
  lines.remove(dat, l, c, l2, c2)
  return ch
end

function ChangeStart:__tostring()
  return string.format('[%s.%s -> %s.%s]', self.l1, self.c1, self.l2, self.c2)
end
function Change:__tostring()
  return string.format('{%s %s.%s %q}', self.k, self.l, self.c, self.s)
end

return M

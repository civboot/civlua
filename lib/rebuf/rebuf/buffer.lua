local pkg = require'pkglib'
local mty = pkg'metaty'
local ds = pkg'ds'
local motion  = pkg'rebuf.motion'
local gap  = pkg'rebuf.gap'

local M = {}
local add, ty = table.insert, mty.ty

M.ChangeId = 0
M.nextChangeId = function() M.ChangeId = M.ChangeId + 1; return M.ChangeId end

M.ChangeStart = mty.record2'ChangeStart' {
  'l1[int]',       'c1[int]',
  'l2[int]',       'c2[int]',
}

M.Change = mty.record2'Change' {
  'k[string]', 's[string]',
  'l[int]',    'c[int]',
}

M.Buffer = mty.record2'Buffer' {
  'id  [int]',
  'gap [Gap]',

  -- recorded changes from update (for undo/redo)
  'changes',
  'changeMax [int]',
  'changeStartI [int]',
  'changeI [int]',
  'mdl',
}

local Buffer, Change, ChangeStart = M.Buffer, M.Change, M.ChangeStart

local function redoRm(ch, b)
  local len = #ch.s - 1; if len < 0 then return ch end
  local l2, c2 = b.gap:offset(len, ch.l, ch.c)
  b.gap:remove(ch.l, ch.c, l2, c2)
  return ch
end

local function redoIns(ch, b)
  b.gap:insert(ch.s, ch.l, ch.c)
  return ch
end

local CHANGE_REDO = { ins=redoIns, rm=redoRm, }
local CHANGE_UNDO = { ins=redoRm, rm=redoIns, }

Buffer.new=function(s)
  return Buffer{
    gap=gap.Gap.new(s),
    changes={}, changeMax=0,
    changeStartI=0, changeI=0,
  }
end

Buffer.addChange=function(b, ch)
  b.changeI = b.changeI + 1; b.changeMax = b.changeI
  b.changes[b.changeI] = ch
  return ch
end
Buffer.discardUnusedStart=function(b)
  if b.changeI ~= 0 and b.changeStartI == b.changeI then
    local ch = b.changes[b.changeI]
    assert(ty(ch) == ChangeStart)
    b.changeI = b.changeI - 1
    b.changeMax = b.changeI
    b.changeStartI = 0
  end
end
Buffer.changeStart=function(b, l, c)
  local ch = ChangeStart{l1=l, c1=c}
  b:discardUnusedStart()
  b:addChange(ch); b.changeStartI = b.changeI
  return ch
end
Buffer.getStart=function(b)
  if b.changeStartI <= b.changeMax then
    return b.changes[b.changeStartI]
  end
end
Buffer.printChanges=function(b)
  for i=1,b.changeMax do
    pnt(b.changes[i], (i == b.changeI) and "<-- changeI" or "")
  end
end

Buffer.changeIns=function(b, s, l, c)
  return b:addChange(Change{k='ins', s=s, l=l, c=c})
end
Buffer.changeRm=function(b, s, l, c)
  return b:addChange(Change{k='rm', s=s, l=l, c=c})
end

Buffer.canUndo=function(b) return b.changeI >= 1 end
-- TODO: shouldn't it be '<=' ?
Buffer.canRedo=function(b) return b.changeI < b.changeMax end

Buffer.undoTop=function(b)
  if b:canUndo() then return b.changes[b.changeI] end
end
Buffer.redoTop=function(b)
  if b:canRedo() then return b.changes[b.changeI + 1] end
end

Buffer.undo=function(b)
  local ch = b:undoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0

  local done = {}
  while ch do
    b.changeI = b.changeI - 1
    add(done, ch)
    if ty(ch) == ChangeStart then break
    else
      assert(ty(ch) == Change)
      CHANGE_UNDO[ch.k](ch, b)
    end
    ch = b:undoTop()
  end
  local o = ds.reverse(done)
  return o
end

Buffer.redo=function(b)
  local ch = b:redoTop(); if not ch then return end
  b:discardUnusedStart(); b.changeStartI = 0
  assert(ty(ch) == ChangeStart)
  local done = {ch}; b.changeI = b.changeI + 1
  ch = b:redoTop(); assert(ty(ch) ~= ChangeStart)
  while ch and ty(ch) ~= ChangeStart do
    b.changeI = b.changeI + 1
    add(done, ch)
    CHANGE_REDO[ch.k](ch, b)
    ch = b:redoTop()
  end
  return done
end

Buffer.append=function(b, s)
  local ch = b:changeIns(s, #b.gap + 1, 1)
  b.gap:append(s)
  return ch
end

Buffer.insert=function(b, s, l, c)
  l, c = b.gap:bound(l, c)
  local ch = b:changeIns(s, l, c)
  b.gap:insert(s, l, c)
  return ch
end

Buffer.remove=function(b, ...)
  local l, c, l2, c2 = gap.lcs(...)
  local lt, ct = motion.topLeft(l, c, l2, c2)
  lt, ct = b.gap:bound(lt, ct)
  local ch = b.gap:sub(l, c, l2, c2)
  ch = (type(ch)=='string' and ch) or table.concat(ch, '\n')
  ch = b:changeRm(ch, lt, ct)
  b.gap:remove(l, c, l2, c2)
  return ch
end

Buffer.len = function(b) return #b.gap end

ChangeStart.__tostring = function(c)
  return string.format('[%s.%s -> %s.%s]', c.l1, c.c1, c.l2, c.c2)
end
Change.__tostring = function(c)
  return string.format('{%s %s.%s %q}', c.k, c.l, c.c, c.s)
end

return M

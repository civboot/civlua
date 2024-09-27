local mty = require'metaty'
--- EdFile: an editable file object, optimized for indexed and consequitive
--- reads and writes
local EdFile = mty'EdFile' {
  'lf   [lines.File]: indexed file',
  'dats [list]: list of Slc | Gap',
  'lens [list]: rolling sum of dat lengths',
  'readonly [bool]',
}

local ds = require'ds'
local log = require'ds.log'
local U3File = require'lines.U3File'
local Gap = require'lines.Gap'
local File = require'lines.File'
local U3File = require'lines.U3File'

local push = table.insert
local getmt = getmetatable
local min, MAXINT = math.min, math.maxinteger
local index, newindex = mty.index, mty.newindex
local construct = mty.construct
local gt, binsearch = ds.lt, ds.binarySearch
local Slc = ds.Slc
local extend, inset, clear = ds.extend, ds.inset, ds.clear
local move, EMPTY = table.move, {}

EdFile.new = function(T, lf)
  return mty.construct(T, {
    lf=lf,
    dats={Slc{si=1, ei=#lf}},
    lens={},
  })
end

EdFile._updateLens = function(ef, max)
  max = max or MAXINT
  local lens, dats, len = ef.lens, ef.dats
  for i=#lens+1, #dats do
    len = (lens[i - 1] or 0) + #dats[i]
    lens[i] = len
    if len >= max then return end
  end
end

EdFile.__len = function(ef)
  ef:_updateLens()
  local l = ef.lens; return l[#l]
end

--- get the index into dats where [$ef[i]] is located
EdFile._datindex = function(ef, i) --> di
  if i < 1 then return end
  local lens = ef.lens; local len = lens[#lens]
  if not len or i > len then ef:_updateLens(i) end
  if i > lens[#lens] then return end
  return binsearch(lens, i, gt) + 1
end

EdFile.__index = function(ef, i)
  if type(i) == 'string' then
    local mt = getmt(ef)
    return rawget(mt, i) or index(mt, i)
  end
  local di = ef:_datindex(i); if not di then return end
  local dat = ef.dats[di]
  i = i - (ef.lens[di-1] or 0) -- i is now index into dat
  return (getmt(dat) == Slc) and ef.lf[dat.si + i - 1]
      or dat[i]
end

--- Create a new EdFile (default idx=lines.U3File()).
EdFile.create = function(T, ...) --> EdFile
  local lf, err = File:create(...)
  if not lf then return nil, err end
  return T:new(lf)
end

EdFile.load = function(T, ...) --> EdFile
  local lf, err = File:load(...)
  if not lf then return nil, err end
  return T:new(lf)
end


EdFile.write = function(ef, ...)
  assert(not ef.readonly, 'attempt to modify readonly file')
  local dats = ef.dats
  local last = dats[#dats]
  ef.lens[#dats] = nil
  if getmt(last) == Slc then
    ef.lf:write(...)
    last.ei = #ef.lf.idx
  else last:write(...) end
end

EdFile.__newindex = function(ef, i, v)
  if type(i) == 'string' then return newindex(ef, i, v) end
  ef:__inset(i, {v}, 1)
end

local EdIter = mty'EdIter' {
  'dats',
  'i [int]: (next) index into EdFile',
  'dati [int]',
  'di [int]: index of dat[dati]',
  'lf [lines.File]: reader of file',
}
getmetatable(EdIter).__call = function(T, ef, si)
  si = si or 1
  local dati = ef:_datindex(si)
  if not dati then return construct(T, {}) end -- empty
  local di = si - (ef.lens[si-1] or 0)
  return construct(T, {
    dats=ef.dats, i=si, dati=dati, di=di, lf=ef.lf:reader(),
  })
end
EdIter.close = function(ei)
  ei.i, ei.di, ei.dati = false
  if ei.lf then ei.lf:close(); ei.lf = nil end
end
EdIter.__call = function(ei) --> iterate
  local i = ei.i; if not i then return end
  local di, dati, dats = ei.di, ei.dati, ei.dats
  local d = dats[dati]
  local r = (getmt(d) == Slc) and ei.lf[d.si + di - 1]
         or d[di]
  assert(r)
  if di < #d          then di       = di + 1
  elseif dati < #dats then di, dati = 1     , dati + 1, 1
  else ei:close(); return i, r end
  ei.i, ei.dati, ei.di = i + 1, dati, di
  return i, r
end

EdFile.iter = function(ef)   return EdIter(ef) end

--- Flush the .lf member (which can only be extended).
--- To write all data to disk use :dump()
EdFile.flush = function(ef) return ef.lf:flush() end

--- Dump EdFile to file or path
EdFile.dumpf = function(ef, f)
  local ef, efx = ef.lf.f, ef.lf.idx
  for i, d in ipairs(ef.dats) do
    if getmt(d) == Slc then
      local sp, ep = efx[d.si], efx[d.si + 1]
      assert(sp == ef:seek('set', sp))
      assert(f:write(ef:read(ep and (ep - sp + 1) or nil)))
    else
      assert(f:write(concat(d, '\n')))
      if i < #ef.dats then assert(f:write'\n') end
    end
  end
end

--- appends to lf for extend when possible.
EdFile.__extend = function(ef, values)
  if #values == 0 then return end
  local dlen = #ef.dats
  local last = ef.dats[dlen]
  if getmt(last) == Slc then
    local lf = ef.lf
    extend(lf, values); last.ei = #lf
  else extend(last, values) end
  local lens = ef.lens
  if dlen == #lens then
    lens[dlen] = lens[dlen] + #values
  end
  return ef
end

----------------------------
-- EdFile.__inset
-- This is the major logic for mutating an EdFile

--- inset the dat, pushing to dats the values that have to be
--- reinserted into the EdFile.dats
local insetDat = function(dats, dat, i, values, rmlen)
  if getmt(dat) ~= Slc then
    inset(dat, i, values, rmlen)
    push(dats, dat)
    return
  end
  local dlen, vlen = #dat, values and #values or 0
  if (vlen == 0) and (rmlen == 0 or i > dlen) then
    push(dats, dat) -- no change
    return
  end
  if i > 1 then
    push(dats, Slc{si=dat.si, ei=i - 1})
  end
  if vlen > 0 then push(dats, Gap(values)) end
  if i + rmlen <= dat.ei then
    push(dats, Slc{si=i + rmlen, ei=dat.ei})
  end
end

--- insert into EdFile's dats.
EdFile.__inset = function(ef, i, values, rmlen)
  assert(not ef.readonly, 'attempt to modify readonly file')
  rmlen = rmlen or 0

  -- General algorith:
  -- * Get the first and last dats in [i:i+rmlen]. Inner dats are dropped.
  -- * Handle Slc types by splitting them
  -- * Handle rmlen for each section individually
  -- * Handle Gaps by joining them
  local lens, df, dl = ef.lens, ef:_datindex(i), nil
  if not df then
    -- special case: extend. This is special because it writes to the file.
    assert(i == #ef + 1, 'i > len+1')
    return ef:__extend(values)
  end

  if rmlen > 0 then -- find last dat to remove (and in-between)
    dl = ef:_datindex(i + rmlen - 1)
    if dl then if (dl - df > 1) then
      -- update rmlen with dropped dats
      rmlen = rmlen - (lens[dl-1]-lens[df + 1])
    elseif df == dl then dl = nil end end
  end

  local dats, rdats, ldat = ef.dats, {}, nil
  local first, fi, ei = dats[df], i - (lens[df-1] or 0)

  -- We handle the first and last items separately. By the end of these
  -- blocks we want them to be of type Gap with the rmlen values removed.
  if getmt(first) == Slc then
    -- split up first slice
    if 1 < fi then
      local slc = Slc{si=first.si, ei=first.si + fi - 2}
      push(rdats, slc)
    end
    if dl then
      rmlen = rmlen - (#first - fi)
      assert(rmlen > 0, 'programmer error')
    elseif (fi + rmlen) <= first.ei then -- put Slc at end
      local slc = Slc{si=(first.si+fi-1) + rmlen, ei=first.ei}
      rmlen, ldat = 0, slc
    end
    fi, first = 1, nil
  else
    local rmfirst = min(rmlen, #first - fi + 1)
    if rmfirst > 0 then
      first:__inset(fi, nil, rmfirst)
      rmlen = rmlen - rmfirst
    end
  end

  local last, li
  if dl then
    last = dats[dl]
    if getmt(last) == Slc then
      if rmlen < #last then
        ldat = Slc{si=last.si + rmlen, ei=last.ei}
      end
      last = nil
    elseif rmlen > 0 then
      last:__inset(1, nil, rmlen); rmlen = 0
    end
  end

  if last then
    if first then first:__extend(last) -- join first+last
    else          first, fi = last, 1 end
  end
  if values and #values > 0 then
    first = first or Gap()
    first:__inset(fi, values, 0)
  end
  if first then push(rdats, first) end
  if ldat  then push(rdats, ldat) end

  -- consolodate Gap objects
  first = dats[df-1]
  if (getmt(first) == Gap) and (getmt(rdats[1]) == Gap) then
    first:__extend(rdats[1]); rdats[1], df = first, df - 1
  end
  local last = rdats[#rdats]
  if dl and (getmt(last) == Gap) and (getmt(dats[dl+1]) == Gap) then
    last:__extend(dats[dl+1]); dl = dl + 1
  end
  move(EMPTY, df, #lens, df, lens) -- clear end lens
  inset(dats, df, rdats, (dl or df) - df + 1)
end

return EdFile

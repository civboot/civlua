local mty = require'metaty'
-- EdFile: an editable file object, optimized for indexed and consequitive
-- reads and writes.
local EdFile = mty'EdFile' {
  'lf   [lines.File]: indexed file',
  'dats [list]: list of Slice | Gap',
  'lens [list]: rolling sum of dat lengths',
}

local ds = require'ds'
local U3File = require'lines.U3File'
local Gap = require'lines.Gap'

local getmt, MAXINT = getmetatable, math.maxinteger
local index, newindex = mty.index, mty.newindex
local gt, binsearch = ds.lt, ds.binarySearch
local Slice = ds.Slice
local inset, clear = ds.inset, ds.clear

-- Create a new EdFile (default idx=lines.U3File()).
EdFile.create = function(T, path, idx) --> EdFile
  local f, err = io.open(path, 'w+'); if not f   then return nil, err end
  if idx then assert(#idx == 0, 'idx must be empty')
  else
    idx, err = U3File:create();       if not idx then return nil, err end
  end
  return mty.construct(T, {
    f=f, idx=idx,
    dats={Slice{si=1, ei=0}},
    lens={0},
  })
end

EdFile._updateLens = function(ef, max)
  max = max or MAXINT
  local lens, dats, len = ef.lens, ef.dats
  for i=#lens+1, #dats do
    len = (lens[i - 1] or 0) + #dats[i]
    lens[i] = len; if len >= max then return end
  end
end

EdFile.__len = function(ef)
  ef:_updateLens(ef)
  local l = ef.lens; return l[#l]
end

-- get the index into dats where ef[i] is located
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
  return (getmt(dat) == Slice) and ef.lf[dat.si + i - 1]
      or dat[i]
end

-- Note to reader: this is a long and complicated-looking function.
-- However, all it is doing is bookeeping Slice vs Gap objects
-- for the inset operation. Because this function exists,
-- we don't need to implement almost any other logic for EdFile
-- to performantly operate like a lines table.
EdFile.__inset = function(ef, i, values, rmlen)
  rmlen = rmlen or 0
  if (rmlen == 0) and (not values or #values == 0) then return end

  -- idats: the dats we are insetting into ef.dats
  -- ds/de: start/end index of ef.dats
  -- l/ll-dat: last[last] dat
  local lf, lens, dats, idats = ef.lf, ef.lens, ef.dats, {}

  -- Get the dats start index
  local ds, dat, ldat, lldat = ef:_datindex(i)
  if not ds then
    ds = #lens; assert(i == lens[ds] + 1, 'newindex OOB')
  end

  -- dat will be the piece of data we are adding values to
  -- it will be pushed onto idats when/if we know what it is.
  dat = dats[ds]
  i = i - (lens[ds-1] or 0) -- i is now index into dat

  -- if dat is a Slice we break it up
  if i > 1 and getmt(dat) == Slice then
    -- break start Slice in half
    push(idats, Slice{si=1, ei=i-1})
    dat = Slice{si=i, ei=dat.ei}
    i, len = 1, dat.ei - i + 1
  end

  -- now we skip dat elements that we will completely remove.
  -- note: rmlen might still be > 0 if dat is a #gap > rmlen.
  local de, len = ds, #dat
  while len < rmlen do -- skip dats that are totally removed
    local dlen = #dat
    len, i, rmlen = dlen, i - dlen, rmlen - dlen
    de = de + 1; dat = dats[de]
  end
  if ds ~= de and len ~= rmlen and getmt(dat) == Slice then
    -- break end Slice off, dat is now completely empty
    lldat = Slice{si=dat.si + rmlen, ei=dat.ei} -- idats[last]
    rmlen, dat = 0, nil
  end

  -- now we insert values into the dat we've found
  if values and #values > 0 then
    if not dat or getmt(dat) == Slice then
      assert(i == 1)
      ldat, dat = dat, Gap()
    end
    dat:inset(i, values, rmlen)
  end

  if dat   then push(idats, dat)   end
  if ldat  then push(idats, ldat)  end
  if lldat then push(idats, lldat) end
  -- TODO: join Slice/Gaps that are in idats

  inset(dats, ds, idats, de - ds + 1)
  clear(lens, ds) -- remove length caches
end

return EdFile

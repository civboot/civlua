-- Get documentation for lua types and syntax. Examples:
--- [##
--- doc{string.find}
--- doc'for'
--- doc'myMod.myFunction'
--- doc{'someMod', --pkg} -- full pkg documentation
--- ]##
---
--- Note: depends on pkg for lookup.
local M = mod and mod'doc' or setmetatable({}, {})
MAIN = MAIN or M

assert(PKG_LOC and PKG_NAMES, 'must use pkglib or equivalent')

local shim = require'shim'
local mty  = require'metaty'
local ds   = require'ds'
local Iter = require'ds.Iter'
local sfmt, srep = string.format, string.rep
local push = table.insert
local pth = require'ds.path'
local pkglib = require'pkglib'
local style = require'asciicolor.style'
local fd = require'fd'

local sfmt, pushfmt = string.format, ds.pushfmt

--- Find the object or name in pkgs
M.find = function(obj) --> Object
  if type(obj) ~= 'string' then return obj end
  return PKG_LOOKUP[obj] or M.getpath(obj) or rawget(_G, obj)
end

local objTyStr = function(obj)
  local ty = type(obj)
  return (ty == 'table') and mty.tyName(mty.ty(obj)) or ty
end
local isConcrete = function(obj)
  return ds.isConcrete(obj) or (getmetatable(obj) == nil)
end

local _construct = function(T, d)
  assert(d.name, 'must set name')
  assert(d.docTy, 'must set docTy')
  return mty.construct(T, d)
end

--- Documentation on a single type
--- These pull together the various sources of documentation
--- from the PKG and META_TY specs into a single object.
---
--- Example: [$metaty.tostring(doc.Doc(myObj))]
M.Doc = mty'Doc' {
  'obj [any]: the object being documented',
  'name[string]', 'pkgname[string]',
  'ty [Type]: type, can be string', 'docTy [string]',
  'path [str]',
  'main [Doc]: main Args, mostly used for PKG',
  'meta [table]: metadata, mostly used for PKG',
  'comments [lines]: comments above item',
  'code [lines]: code which defines the item',
  'call   [function]',
  'fields [table{name=DocItem}]: (for metatys)',
  'values [table]: raw values that are not the other types',
  'tys    [table]: table of values',
  'fns    [table]: methods or functions',
  'mods   [table]: sub modules (for PKG)',
  'lvl    [int]: level inside another type (nil or 1)',
}
getmetatable(M.Doc).__call = _construct
M.Doc.__tostring = function(d) return sfmt('Doc%q', d.name) end

M.DocItem = mty'DocItem' {
  'obj [any]',
  'name', 'pkgname [string]', 'ty [string]', 'docTy [string]',
  'path [string]',
  'default [any]', 'doc [string]'
}
getmetatable(M.DocItem).__call = _construct
M.DocItem.__tostring = function(di) return sfmt('DocItem%q', di.name) end

--- return the object's "document type"
M.type = function(obj)
  return type(obj) == 'function' and 'Function'
      or pkglib.isPkg(obj)       and 'Package'
      or pkglib.isMod(obj)       and 'Module'
      or mty.isRecord(obj)       and 'Record'
      or (type(obj) == 'table')  and 'Table'
      or 'Value'
end

--- get a Doc or DocItem. If expand is true then recurse.
M.construct = function(obj, key, expand, lvl) return M._Construct{}(obj, key, expand, lvl) end

--- internal type to construct Doc and DocItems
M._Construct = mty'_Construct' {
  'done [table]: objects already documented',
}
getmetatable(M._Construct).__call = function(T, t)
  return mty.construct(T, {done={}})
end

M._Construct.__call = function(c, obj, key, expand, lvl) --> Doc | DocItem
  assert(obj)
  expand = expand or 0
  local docTy = assert(M.type(obj))
  if docTy == 'Package' then return c:pkg(obj, expand) end
  local name, path = M.modinfo(obj)
  local d = {
    obj=obj, path=path, docTy=docTy,
    name=assert(key or name), pkgname=PKG_NAMES[obj],
    ty=objTyStr(obj),
  }
  if c.done[obj] then return M.DocItem(d) end
  c.done[obj] = true
  local comments, code = M.findcode(path)
  if comments then M.stripComments(comments) end
  if comments and #comments == 0 then comments = nil end
  if code     and #code == 0     then code = nil end
  if expand <= 0 or (not comments and isConcrete(obj))
    and (docTy == 'Table' or docTy == 'Value') then
    return M.DocItem(d)
  end
  d.lvl, d.comments, d.code = lvl, comments, code
  d = M.Doc(d)
  if type(obj) ~= 'table' then return d end
  local mt = getmetatable(obj)
  if mt ~= nil and type(mt) ~= 'table' then return d end

  d.call = mty.getmethod(obj, '__call')
  local t = ds.copy(obj) -- we will remove from t as we go
  setmetatable(t, nil)

  -- get fields as DocItems
  d.fields = rawget(obj, '__fields'); if d.fields then
    d.fields = ds.copy(d.fields)
    local fdocs = rawget(obj, '__docs') or {}
    for i, field in ipairs(d.fields) do
      t[field] = nil
      local ty = d.fields[field]
      ty = type(ty) == 'string' and M.cleanFieldTy(ty) or nil
      d.fields[field] = M.DocItem {
        name=field, ty=ty, default=rawget(obj, field),
        doc = fdocs[field], docTy = 'Field',
      }
    end
  end

  -- get other buckets
  d.fns, d.tys, d.mods = {}, {}, {}
  for k, v in pairs(t) do
    if type(v) == 'function' then
      if PKG_NAMES[v] then d.fns[k] = v; t[k] = nil end
      -- else keep as "value"
    elseif pkglib.isMod(v)  then d.mods[k]   = v; t[k] = nil
    elseif mty.isRecord(v)  then d.tys[k]    = v; t[k] = nil
    end
  end

  local function finish(attr, lvl)
    local t = d[attr]; ds.pushSortedKeys(t)
    if #t == 0 then d[attr] = nil; return end
    for _, k in ipairs(t) do
      t[k] = c(t[k], k, expand - 1, lvl)
    end
  end
  d.values = t
  if d.fields and #d.fields == 0 then d.fields = nil end
  finish'values'; finish'tys'; finish'mods'
  finish('fns', (d.docTy == 'Record' or d.docTy == 'Table') and 1 or nil)
  return d
end

--- compare so items with [$.] come last in a sort
local function modcmp(a, b)
  if a:find'%.' then
    if not b:find'%.' then return false end -- b is first
  elseif b:find'%.'   then return true  end -- a is first
  return a < b
end

M._Construct.pkg = function(c, pkg, expand) --> Doc
  local d = M.Doc{
    docTy = 'Package', name = pkg.name, path = pkg.PKGDIR,
  }
  d.meta = {
    summary = pkg.summary, version = pkg.version,
    homepage = pkg.homepage,
  }
  if pkg.main then
    local m = mty.assertf(
      M.find(pkg.main), 'PKG %s: main not found', d.name)
    m = c(m, nil, expand - 1)
    d.main = M.Doc {
      name = pkg.main, docTy = 'Args',
      comments = m.comments, fields = m.fields,
    }
  end
  d.mods = pkglib.modules(pkg.srcs)
  ds.pushSortedKeys(d.mods, modcmp)
  for i, mname in ipairs(d.mods) do
    d.mods[mname] = c(M.find(mname), mname, expand - 1)
  end
  return d
end

---------------------
-- Helpers

local VALID = {['function']=true, table=true}

M.modinfo = function(obj) --> (name, loc)
  if type(obj) == 'function' then return mty.fninfo(obj) end
  if ds.isConcrete(obj)      then return type(obj), nil end
  local name, loc = PKG_NAMES[obj], PKG_LOC[obj]
  name = name or (type(obj) == 'table') and rawget(obj, '__name')
  return name, loc
end

M.findcode = function(loc) --> (commentLines, codeLines)
  if loc == nil then return end
  if type(loc) ~= 'string' then loc = select(2, M.modinfo(loc)) end
  if not loc then return end
  local path, locLine = loc:match'(.*):(%d+)'
  if not path then error('loc path invalid: '..loc) end
  local l, lines, locLine = 1, ds.Deq{}, tonumber(locLine)
  local l, lines = 1, ds.Deq{}
  for line in io.lines(path) do
    lines:push(line); if #lines > 256 then lines:pop() end
    if l == locLine then break end
    l = l + 1
  end
  assert(l == locLine, 'file not long enough')
  lines = ds.reverse(table.move(lines, lines.left, lines.right, 1, {}))
  local code, comments = {}, {}
  for l, line in ipairs(lines) do
    if line:find'^%w[^-=]+=' then
      table.move(lines, 1, l, 1, code); break
    end
  end
  for l=#code+1, #lines+1 do local
    line = lines[l]
    if not line or not line:find'^%-%-%-' then
      table.move(lines, #code+1, l-1, 1, comments); break
    end
  end
  return ds.reverse(comments), ds.reverse(code)
end

M.cleanFieldTy = function(ty)
  return ty:match'^%[.*%]$' and ty:sub(2,-2) or ty
end

M.stripComments = function(com)
  if #com == 0 then return end
  local ind = com[1]:match'^%-%-%-(%s+)' or ''
  local pat = '^%-%-%-'..string.rep('%s?', #ind)..'(.*)%s*'
  for i, l in ipairs(com) do com[i] = l:match(pat) or l end
end

--- get any path with [$.] in it. This is mostly used by help/etc functions
M.getpath = function(path)
  require'doc.lua' -- ensure that builtins are included
  path = type(path) == 'string' and ds.splitList(path, '%.') or path
  local obj
  for i=1,#path do
    local v = obj and ds.get(obj, ds.slice(path, i))
    if v then return v end
    obj = pkglib.get(table.concat(path, '.', 1, i))
  end
  return obj
end

---------------------
-- Format to CXT

M.fmtDocItem = function(f, di)
  local name = di.name and sfmt('[$%s]', di.name) or '(unnamed)'
  local ty = di.ty and sfmt('\\[%s\\]', di.ty) or ''
  local path = di.path and sfmt('[/%s]', pth.nice(di.path))
  local default = di.default and mty.format('= [$%q]', di.default)
  if path and default then path = '\n'..path end
  path, default = path or '', default or ''
  if path:sub(1,1) == '\n' or (di.doc and di.doc ~= '') then
    f:level(1)
    pushfmt(f, '%-16s | %s %s%s\n%s', name, ty, default, path, di.doc)
    f:level(-1)
  else
    pushfmt(f, '%-16s | %s %s%s', name, ty, default, path)
  end
end

M.fmtAttr = function(f, name, attr)
  if not attr or not next(attr) then return end
  local docs, dis = {}, {}
  for _, k in ipairs(attr) do
    if mty.ty(attr[k]) == M.Doc then push(docs, k)
    else push(dis, k) end -- DocItem and values
  end
  if #dis > 0 then
    pushfmt(f, '\n[*%s: ] [{table}', name)
    for i, k in ipairs(dis) do
      local v = attr[k]
      push(f, '\n+ ')
      if mty.ty(v) == M.DocItem then M.fmtDocItem(f, v)
      else pushfmt(f, '[*%s] | [##', k); f(v); push(f, ']') end
    end
    push(f, '\n]')
  end
  if #docs > 0 then
    for i, k in ipairs(docs) do
      push(f, '\n'); M.fmtDoc(f, attr[k])
    end
  end
end

local HEADERS = {Package=1, Module=2, Record=3, Table=3, Args=2}
M.docHeader = function(docTy, lvl)
  if docTy == 'Function' then return 3 + (lvl or 0) end
  return assert(HEADERS[docTy])
end

M.fmtMeta = function(f, m)
  pushfmt(f, '[{table}')
  if m.summary then pushfmt(f, '\n+ [*summary] | %s', m.summary) end
  pushfmt(f, '\n+ [*version] | [$%s]', m.version or '(no version)')
  if m.homepage then pushfmt(f, '\n+ [*homepage] | %s', m.homepage) end
  pushfmt(f, '\n]')
end

M.fmtDoc = function(f, d)
  if d.docTy ~= 'Args' then assert(d.docTy, tostring(d))
    local path = d.path and sfmt(' [/%s]', pth.nice(d.path)) or ''
    local name = d.pkgname or d.name
    pushfmt(f, '[{h%s}%s [{style=api}%s]%s]',
            M.docHeader(d.docTy, d.lvl),
            assert(d.docTy),
            d.pkgname or d.name or '(unnamed)', path)
  end
  if d.meta then M.fmtMeta(f, d.meta) end
  if d.comments then
    for i, l in ipairs(d.comments) do
      push(f, '\n'); push(f, l)
    end
  end
  if d.main then
    M.fmtDoc(f, d.main)
  end
  if type(d.obj) == 'function' and d.code and d.code[1] then
    if d.comments or d.meta then push(f, '\n') end
    pushfmt(f, '\n[$%s]', d.code[1])
  end
  local any = d.fields or d.values or d.tys or d.fns
  if any or d.mods then push(f, '\n') end
  if d.fields then
    M.fmtAttr(f, d.docTy == 'Args' and 'Named Args' or 'Fields', d.fields)
  end
  if d.values then M.fmtAttr(f, 'Values',  d.values) end
  if d.tys    then M.fmtAttr(f, 'Records', d.tys) end
  if d.fns then
    local name = (d.docTy == 'Record') and 'Methods' or 'Functions'
    M.fmtAttr(f, name, d.fns)
  end
  if d.mods then
    if any then push(f, '\n') end
    for _, m in ipairs(d.mods) do
      push(f, '\n'); M.fmtDoc(f, d.mods[m])
    end
  end
end

M.fmt = function(f, d)
  if     mty.ty(d) == M.Doc     then M.fmtDoc(f, d)
  elseif mty.ty(d) == M.DocItem then M.fmtDocItem(f, d)
  else error'not a Doc or DocItem' end
  return f
end

--- Get documentation for an object or package. Usage: [{## lang=lua}
---  help 'path.of.object'
--- ]##
---
--- If no path is given shows all available packages.
M.Args = mty'Args' {
  'pkg [bool]: if true uses PKG.lua (and all sub-modules)',
  'full [bool]: if true displays the full API of all pkgs/mods',
  'local [bool]: if true only unpacks local pkgs/mods',
  'color [string|bool]: whether to use color [$true false always never]',
}

M.main = function(args)
  args = M.Args(shim.parseStr(args))
  local to = style.Styler:default(io.stdout, args.color)
  if args.help then return M.styleHelp(to, M.Args) end
  local obj, expand = args[1], args.full and 10 or 1
  assert(obj, 'arg[1] must be the item to find')
  local c = M._Construct{}
  local d;
  if args.pkg then
    obj = pkglib.getpkg(obj) or error('could not find pkg: '..obj)
    d = c:pkg(obj, expand)
  else
    if type(obj) == 'string' then
      obj = M.find(obj) or error('could not find obj: '..obj)
    end
    d = c(obj, nil, expand)
  end
  local f = mty.Fmt{}
  M.fmt(f, d)
  require'cxt.term'{table.concat(f), to=to}
  to:write'\n'
end
getmetatable(M).__call = function(_, args) return M.main(args) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M

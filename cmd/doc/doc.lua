--- Get documentation for lua types and syntax.
--- Examples: [{## lang=lua}
--- doc{string.find}
--- doc'for'
--- doc'myMod.myFunction'
--- doc{'someMod', --pkg} -- full pkg documentation
--- ]##
---
--- ["Note: depends on pkg for lookup]
local M = mod and mod'doc' or setmetatable({}, {})
MAIN = MAIN or M

assert(PKG_LOC and PKG_NAMES, 'must use pkglib or equivalent')

local pkglib = require'pkglib'
local shim = require'shim'
local mty  = require'metaty'
local fd = require'fd'
local fmt  = require'fmt'
local ds   = require'ds'
local pth = require'ds.path'
local Iter = require'ds.Iter'
local lines = require'lines'
local style = require'asciicolor.style'
local cxt = require'cxt'

local escape = cxt.escape
local sfmt, srep = string.format, string.rep
local push = table.insert

local sfmt, pushfmt = string.format, ds.pushfmt

local INTERNAL = '(internal)'
local COMMAND_NAME = 'when executed directly'

--- Find the object or name in pkgs
M.find = function(obj) --> Object
  if type(obj) ~= 'string' then return obj end
  return PKG_LOOKUP[obj] or M.getpath(obj)
      or ds.rawget(G, ds.dotpath(obj))
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
M.Doc = mty'Doc' {
  'obj [any]: the object being documented',
  'name[string]', 'pkgname[string]',
  'ty [Type]: type, can be string', 'docTy [string]',
  'path [str]',
  'main [Doc]: main Args, mostly used for PKG',
  'meta [table]: metadata, mostly used for PKG',
  'comments [lines]: comments above item',
  'code   [lines]: code which defines the item',
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

--- get fields as DocItems removing from t
local setFields = function(d, t)
  d.fields = rawget(d.obj, '__fields'); if not d.fields then return end
  d.fields = ds.copy(d.fields)
  local fdocs = rawget(d.obj, '__docs') or {}
  for i, field in ipairs(d.fields) do
    t[field] = nil
    local ty = d.fields[field]
    ty = type(ty) == 'string' and M.cleanFieldTy(ty) or nil
    d.fields[field] = M.DocItem {
      name=field, ty=ty, default=rawget(d.obj, field),
      docTy = 'Field',
      doc = fdocs[field] and cxt.checkParse(fdocs[field], field),
    }
  end
end

M._Construct.__call = function(c, obj, key, expand, lvl) --> Doc | DocItem
  assert(obj ~= nil)
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
  if comments then
    M.stripComments(comments)
    if #comments == 0 then comments = nil
    else cxt.checkParse(comments, pth.nice(path)) end
  end
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

  setFields(d, t)

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
    local t = d[attr]; ds.pushSortedKeys(t, fmt.cmpDuck)
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
    docTy = 'Package', name = pkg.name, path = pkg.dir,
  }
  d.meta = {
    summary = pkg.summary, version = pkg.version,
    homepage = pkg.homepage,
  }
  if pkg.doc then
    d.comments = lines.load(pth.concat{pkg.dir, pkg.doc})
  end
  if pkg.main then
    local m = fmt.assertf(
      M.find(pkg.main), 'PKG %s: main not found', d.name)
    d.main = c:main(m)
  end
  d.mods = pkglib.modules(pkg.srcs)
  ds.pushSortedKeys(d.mods, modcmp)
  for i, mname in ipairs(d.mods) do
    d.mods[mname] = c(M.find(mname), mname, expand - 1)
  end
  return d
end

M._Construct.main = function(c, obj) --> Doc
  local d = c(obj, nil, 1)
  return M.Doc {
    name = d.name, docTy = 'Command',
    comments = d.comments, fields = d.fields,
  }
end

---------------------
-- Helpers

local VALID = {['function']=true, table=true}

M.modinfo = function(obj) --> (name, loc)
  if type(obj) == 'function' then return mty.fninfo(obj) end
  if ds.isConcrete(obj)      then return type(obj), nil end
  local name, loc = PKG_NAMES[obj], PKG_LOC[obj]
  name = name or (type(obj) == 'table') and rawget(obj, '__name')
  if loc and loc:find'%[' then loc = INTERNAL end
  return name, loc
end

M.findcode = function(loc) --> (commentLines, codeLines)
  if not loc or loc == INTERNAL then return end
  if type(loc) ~= 'string' then loc = select(2, M.modinfo(loc)) end
  if not loc or loc:find'%[' then return end
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
    local v = obj and ds.rawget(obj, ds.slice(path, i))
    if v then return v end
    obj = pkglib.get(table.concat(path, '.', 1, i))
  end
  return obj
end

---------------------
-- Format to CXT

M.fmtDocItem = function(f, di)
  local name = di.name and sfmt('[$%s]', escape(di.name or '(unnamed)'))
  local ty = di.ty and sfmt('\\[%s\\]', escape(di.ty)) or ''
  local path = di.path and sfmt('[/%s]', escape(pth.nice(di.path)))
  local default = di.default and ('= '..cxt.code(fmt(di.default)))
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
      else pushfmt(f, '[*%s] | %s', k, cxt.code(fmt(v))) end
    end
    push(f, '\n]')
  end
  if #docs > 0 then
    for i, k in ipairs(docs) do
      push(f, '\n'); M.fmtDoc(f, attr[k])
    end
  end
end

local HEADERS = {Package=1, Module=2, Record=3, Table=3, Command=2, Value=4}
M.docHeader = function(docTy, lvl)
  if docTy == 'Function' then return 3 + (lvl or 0) end
  return assert(HEADERS[docTy], docTy)
end

M.fmtMeta = function(f, m)
  pushfmt(f, '[{table}')
  if m.summary then pushfmt(f, '\n+ [*summary] | %s', m.summary) end
  pushfmt(f, '\n+ [*version] | [$%s]', m.version or '(no version)')
  if m.homepage then pushfmt(f, '\n+ [*homepage] | %s', m.homepage) end
  pushfmt(f, '\n]')
end

M.fmtDoc = function(f, d)
  local path = d.path and sfmt(' [/%s]', escape(pth.nice(d.path))) or ''
  local name = d.pkgname or d.name
  pushfmt(f, '[{h%s}%s [{style=api}%s]%s]',
          M.docHeader(d.docTy, d.lvl),
          escape(assert(d.docTy)),
          (d.docTy == 'Command') and COMMAND_NAME
          or d.pkgname or d.name or '(unnamed)',
          path)
  if d.meta then M.fmtMeta(f, d.meta) end
  if type(d.obj) == 'function' and d.code and d.code[1] then
    local sig = d.code[1]:match'function.-(%(.-%).*)'
    if sig then push(f, '\nSignature: '); pushfmt(f, '[$%s]', sig) end
  end
  if d.comments then
    for i, l in ipairs(d.comments) do
      push(f, '\n'); push(f, l)
    end
  end
  if d.main then
    M.fmtDoc(f, d.main)
  end
  local any = d.fields or d.values or d.tys or d.fns
  if any or d.mods then push(f, '\n') end
  if d.fields then
    M.fmtAttr(f, d.docTy == 'Command' and 'Named Args' or 'Fields', d.fields)
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
      push(f, '\n'); M.fmt(f, d.mods[m])
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
  'help [bool]: get help',
  'to   [path]: the output. If ends in [$.html] then auto-converts to html',
  'pkg  [deep|bool]: if true uses PKG.lua (and all sub-modules).'
    ..' If "deep" also uses PKG.pkgs',
  'expand [int|bool]: expand to depth (expand=true means expand=10)', expand=1,
  'local [bool]: if true only unpacks local pkgs/mods',
}

local function fmtPkg(f, construct, pkg, expand, deep)
  pkg = pkglib.isPkg(pkg) and pkg
     or pkglib.getpkg(pkg) or error('could not find pkg: '..pkg)
  fmt.print('!! fmtPkg', pkg.name, pkg.dir, expand, deep)
  M.fmt(f, construct:pkg(pkg, expand))
  if deep and pkg.pkgs then
    for _, dir in ipairs(pkg.pkgs) do
      local subp = pkglib.loadpkg(dir)
      f:write'\n\n'
      fmtPkg(f, construct, subp, expand, deep)
    end
  end
  return pkg
end

M.main = function(args)
  args = M.Args(shim.parseStr(args))
  if args.help then return M.styleHelp(io.fmt, M.Args) end
  local obj, expand = args[1], args.expand == true and 10 or args.expand
  assert(obj, 'arg[1] must be the item to find')
  local to = args.to and shim.file(args.to) or nil
  local f, c = fmt.Fmt{to=to}, M._Construct{}
  if args.pkg then fmtPkg(f, c, obj, expand, args.pkg == 'deep')
  else
    if type(obj) == 'string' then
      obj = M.find(obj) or error('could not find obj: '..obj)
    end
    local name = (type(obj) == 'string') and obj or nil
    M.fmt(f, c(obj, name, expand))
  end
  if to then to:write'\n'; to:flush(); to:close()
  else
    require'cxt.term'{table.concat(f), out=io.fmt}
    io.fmt:write'\n'
  end
end
getmetatable(M).__call = function(_, args) return M.main(args) end

if M == MAIN then
  M.main(shim.parse(arg)); os.exit(0)
end
return M

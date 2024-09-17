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

assert(PKG_LOC and PKG_NAMES, ERROR)

local shim = require'shim'
local mty  = require'metaty'
local ds   = require'ds'
local sfmt, srep = string.format, string.rep
local push = table.insert
local pth = require'ds.path'
local pkglib = require'pkglib'
local style = require'asciicolor.style'
local fd = require'fd'

local sfmt, pushfmt = string.format, ds.pushfmt

---------------------
-- Doc and DocItem

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
    if line:find'^%w[^-=]+=' then table.move(lines, 1, l, 1, code); break end
  end
  for l=#code+1, #lines do local
    line = lines[l]
    if not line:find'^%-%-%-' then
      table.move(lines, #code+1, l-1, 1, comments); break
    end
  end
  return ds.reverse(comments), ds.reverse(code)
end

M.DocItem = mty'DocItem' {
  'name', 'ty [string]', 'path [string]',
  'default [any]', 'doc [string]'
}

--- Documentation on a single type
--- These pull together the various sources of documentation
--- from the PKG and META_TY specs into a single object.
---
--- Example: [$metaty.tostring(doc.Doc(myObj))]
M.Doc = mty'Doc' {
  'obj [any]: the object being documented',
  'name', 'ty [Type]: type, can be string',
  'path [str]',
  'comments [lines]: comments above item',
  'code [lines]: code which defines the item',
  'fields [table{name=DocItem}]',
  'other [table{name=DocItem}]: methods and constants',
}

M.fmtItems = function(f, items)
  pushfmt(f, '[{table}')
  for i, item in ipairs(items) do push(f, '\n+ '); f(item) end
  push(f, '\n]')
end
local fmtAttrs = function(d, f)
  if d.fields and next(d.fields) then
    push(f, '\n[*Fields:] '); M.fmtItems(f, d.fields)
  end
  if d.other and next(d.other) then
    push(f, '\n[*Other:] '); M.fmtItems(f, d.other)
  end
end

M.Doc.__fmt = function(d, f)
  local path = d.path and sfmt(' [/%s]', pth.nice(d.path)) or ''
  local name = PKG_NAMES[d.obj]
  local prefix = type(d.obj) == 'function' and 'Function'
              or pkglib.isMod(d.obj) and 'Module'
              or mty.isRecord(d.obj) and 'Record'
              or (type(d.obj) == 'table') and 'Table'
              or type(d.obj)
  pushfmt(f, '[{h%s}%s [{style=api}%s]%s]', f:getIndent() + 2,
          prefix, name or d.name or '(unnamed)', path)
  if type(d.obj) == 'function' and d.code and d.code[1] then
    pushfmt(f, '\n[$%s]', d.code[1])
  end
  for i, l in ipairs(d.comments or {}) do
    push(f, '\n'); push(f, l)
  end
  fmtAttrs(d, f)
end

M.DocItem.typeStr = function(di) return di.ty and mty.tyName(di.ty) end
M.DocItem.defaultStr = function(di)
  return di.default ~= nil and mty.format(' = %q', di.default)
end
local function diFullFmt(f, name, ty, path, doc)
  f:incIndent(); pushfmt(f, '%-16s | %-20s %s%s', name, ty, path, doc)
  f:decIndent()
end
M.DocItem.__fmt = function(di, f)
  local name = di.name and sfmt('[$%s]', di.name) or '(unnamed)'
  local ty = di.ty and sfmt('\\[%s\\]', di.ty) or ''
  local path = di.path and sfmt('[/%s]', pth.nice(di.path))
  local default = di.default and mty.format('= [$%q]', di.default)
  if path and default then path = '\n'..path end
  path, default = path or '', default or ''
  if path:sub(1,1) == '\n' or (di.doc and di.doc ~= '') then
    f:incIndent()
    pushfmt(f, '%-16s | %s %s%s\n%s', name, ty, default, path, di.doc)
    f:decIndent()
  else
    pushfmt(f, '%-16s | %s %s%s', name, ty, default, path)
  end
end

local function cleanFieldTy(ty)
  return ty:match'^%[.*%]$' and ty:sub(2,-2) or ty
end

M.fields = function(obj)
  local fields = rawget(obj, '__fields')
  if not fields then return end
  local out = {}
  local docs = rawget(obj, '__docs') or {}
  for _, field in ipairs(fields) do
    local ty = fields[field]
    ty = type(ty) == 'string' and cleanFieldTy(ty) or false
    push(out, M.DocItem{
      name=field, ty=ty and sfmt('[@%s]', ty),
      default=rawget(obj, field),
      doc = docs[field],
    })
  end
  return out
end

getmetatable(M.Doc).__call = function(T, obj)
  local name, path = M.modinfo(obj)
  local d = mty.construct(T, {
    obj=obj, name=name, path=path,
    ty=mty.tyName(mty.ty(obj)),
  })
  d.comments, d.code = M.findcode(path)
  if d.comments then M.stripComments(d.comments) end
  if type(obj) ~= 'table' then return d end
  if type(getmetatable(obj)) ~= 'table' then return d end

  -- fields
  d.fields, d.other = M.fields(obj) or {}, {}
  local other = ds.copy(obj)
  local fields = rawget(obj, '__fields')
  if fields then for k in pairs(other) do -- remove shared fields
    if fields[k] then other[k] = nil end
  end end
  other = ds.orderedKeys(other)
  for _, k in ipairs(other) do
    local v = obj[k]; local ty = type(v)
    local ty = (ty == 'table') and mty.tyName(mty.ty(v)) or ty
    push(d.other, M.DocItem {
      name=k, ty=sfmt('[@%s]', ty),
      path=select(2, M.modinfo(v)),
    })
  end
  return d
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

--- Find the object or name in pkgs
M.find = function(obj) --> Object
  if type(obj) ~= 'string' then return obj end
  return PKG_LOOKUP[obj] or M.getpath(obj) or rawget(_G, obj)
end

-- compare so items with [$.] come last in a sort
local function modcmp(a, b)
  if a:find'%.' then
    if not b:find'%.' then return false end -- b is first
  elseif b:find'%.'   then return true  end -- a is first
  return a < b
end

--- expand a module's documentation
M.fmtmod = function(f, mod, skip) --> Fmt
  local d = M.Doc(mod)
  pushfmt(f, '[{h2}Module %s [/%s]]\n', d.name, d.path)
  ds.extend(f, table.concat(d.comments, '\n'))
  if skip then
    local rm = {}; for k, obj in pairs(mod) do
      local name = PKG_NAMES[obj]; if skip[name] then push(rm, name) end
    end
    for _, k in rm do mod[k] = nil end
  end
  local keys = ds.orderedKeys(mod)
  for i, k in ipairs(keys) do
    local obj = mod[k]
    if skip and skip[PKG_NAMES[obj]] then goto continue end
    f:incIndent(); f(M.Doc(mod[k])); f:decIndent()
    if i < #keys then push(f, '\n\n') end
    ::continue::
  end
  return f
end

--- expand a PKG's documentation
M.fmtpkg = function(f, pkgname) --> Fmt
  local pkg, pkgdir = pkglib.getpkg(pkgname)
  if not pkg then error('could not find pkg '..pkgname) end
  pushfmt(f, '[{h1}Package %s [/%s/PKG.lua]]\n', pkgname, pth.nice(pkgdir))
  if pkg.summary then pushfmt(f, '%s', pkg.summary) end
  push(f, ' [{table}')
  pushfmt(f, '\n+ [*version] | [$%s]', pkg.version or '(no version)')
  if pkg.homepage then pushfmt(f, '\n+ [*homepage] | %s', pkg.homepage) end
  if pkg.main then push(f, '\n+ [*main()] | can be run as script') end
  push(f, ']\n')

  local mods = ds.copy(pkglib.modules(pkg.srcs))
  local skip = {}
  if pkg.main then
    local main = M.find(pkg.main)
              or error('could not find PKG.main = '..pkg.main)
    M.fmthelp(f, main); skip[PKG_NAMES[main]] = true
  end
  mods = ds.sort(ds.keys(mods), modcmp)
  for i, modname in ipairs(mods) do
    local obj = pkglib.get(modname)
    if pkglib.isMod(obj) then M.fmtmod(f, obj) else f(M.Doc(obj)) end
    if i < #mods then f:write'\n\n' end
  end
  return f
end
--- return the pkg docs as a string.
M.pkgstr = function(pkgname) return table.concat(M.fmtpkg(mty.Fmt{}, pkgname)) end

--- return the formatted Doc for [$obj]
--- If [$obj] is a string it is looked up in pkgs.
M.docstr = function(obj) --> string
  obj = M.find(obj) or error('not found: '..mty.tostring(args[1]))
  return table.concat(mty.Fmt{}(M.Doc(obj)))
end


M.fmthelp = function(f, Args)
  local d = M.Doc(Args)
  for i, line in ipairs(d.comments or {}) do
    f:write(line); if i < #d.comments then f:write'\n' end
  end
  if d.fields and #d.fields > 0 then
    f:write'\nNamed args: '; M.fmtItems(f, d.fields)
  end
  return f
end

--- Get the helpstr for Args type (comments + fields).
---
--- This is used if a function has an associated type for just arg-checking.
M.helpstr = function(Args) --> string
  return table.concat(M.fmthelp(mty.Fmt{}, Args))
end

M.styleHelp = function(styler, Args) require'cxt.term'{M.helpstr(Args), to=styler} end

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
  local str = args.pkg and M.pkgstr(args[1]) or M.docstr(args[1])
  require'cxt.term'{str, to=to}
  to:write'\n'
end
getmetatable(M).__call = function(_, args) return M.main(args) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M

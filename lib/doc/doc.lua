-- Get documentation for lua types and syntax. Examples:
--- [##
--- doc{string.find}
--- doc'for'
--- doc'myMod.myFunction'
--- doc{'someMod', --pkg} -- full pkg documentation
--- ]##
---
--- Note: depends on pkg for lookup.
local M = mod and mod'doc' or {}; MAIN = MAIN or M
local builtin = require'doc.lua'

assert(PKG_LOC and PKG_NAMES, ERROR)

local shim = require'shim'
local mty  = require'metaty'
local ds   = require'ds'
local sfmt = string.format
local push = table.insert
local pth = require'ds.path'
local pkglib = require'pkglib'

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

local function fmtItems(f, items, name)
  pushfmt(f, '[{table}')
  pushfmt(f, '\n+ [*%s]', name)
  for i, item in ipairs(items) do
    push(f, '\n+ '); f(item)
  end
  push(f, '\n]')
end
local fmtAttrs = function(d, f)
  if d.fields and next(d.fields) then
    push(f, '\n'); fmtItems(f, d.fields, 'Fields')
  end
  if d.other  and next(d.other) then
    push(f, '\n'); fmtItems(f, d.other, 'Methods, Etc')
  end
end

M.Doc.__fmt = function(d, f)
  local path = d.path and sfmt(' [/%s]', pth.nice(d.path)) or ''
  local ty = d.ty and sfmt(' [@%s]', d.ty) or ''
  local prefix = type(d.obj) == 'function' and 'Function'
              or pkglib.isMod(d.obj) and 'Module'
              or mty.isRecord(d.obj) and 'Record'
              or type(d.obj)
  pushfmt(f, '[{h%s}%s [:%s]%s%s ]\n', f:getIndent() + 2,
          prefix, d.name, path, ty)
  if type(d.obj) == 'function' and d.code and d.code[1] then
    pushfmt(f, '[$%s]\n', d.code[1])
  end
  for i, l in ipairs(d.comments or {}) do
    push(f, l); if i < #d.comments then push(f, '\n') end
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
  d.fields, d.other = {}, {}
  local fields = rawget(obj, '__fields')
  if fields then
    local docs   = rawget(obj, '__docs') or {}
    for _, field in ipairs(fields) do
      local ty = fields[field]
      ty = type(ty) == 'string' and cleanFieldTy(ty) or false
      push(d.fields, M.DocItem{
        name=field, ty=ty and sfmt('[@%s]', ty),
        default=rawget(obj, field),
        doc = docs[field],
      })
    end
  end
  local other = ds.copy(obj)
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
  return PKG_LOOKUP[obj] or rawget(_G, obj) or M.getpath(obj)
end

-- compare so items with [$.] come last in a sort
local function modcmp(a, b)
  if a:find'%.' then
    if not b:find'%.' then return false end -- b is first
  elseif b:find'%.'   then return true  end -- a is first
  return a < b
end

--- expand a module's documentation
M.fmtmod = function(f, mod) --> Fmt
  local d = M.Doc(mod)
  pushfmt(f, '[{h2}Module %s [/%s]]\n', d.name, d.path)
  ds.extend(f, table.concat(d.comments, '\n'))
  for _, k in ipairs(ds.orderedKeys(mod)) do
    push(f, '\n'); f:incIndent()
    f(M.Doc(mod[k]))
    f:decIndent(); push(f, '\n')
  end
  return f
end

--- expand a PKG's documentation
M.fmtpkg = function(f, pkgname) --> Fmt
  local pkg, pkgdir = pkglib.getpkg(pkgname)
  if not pkg then error('could not find pkg '..pkgname) end
  pushfmt(f, '[{h1}Package %s [/%s/PKG.lua]]\n', pkgname, pth.nice(pkgdir))
  local mods = pkglib.modules(pkg.srcs)
  push(f, '\n')
  for _, modname in ipairs(ds.sort(ds.keys(mods), modcmp)) do
    local obj = pkglib.get(modname)
    if pkglib.isMod(obj) then M.fmtmod(f, obj) else f(M.Doc(obj)) end
    push(f, '\n\n')
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

--- [$help 'path.of.object']
---
--- If no path is given shows all available packages
--- (filter with [$local=true])
M.Cmd = mty'Cmd' {
  'pkg [bool]: if true uses PKG.lua (and all sub-modules)',
  'cmds [bool]: show all modules with a .exe function (intended to run as a command)',
  'full [bool]: if true displays the full API of all pkgs/mods',
  'local [bool]: if true only unpacks local pkgs/mods',
  'color [string|bool]: whether to use color [$true false always never]',
}

M.exe = function(args, isExe)
  args = M.Cmd(shim.parseStr(args))
  if args.pkg then return M.pkg(args[1]) end
  local obj = assert(args[1], 'must provide object to find docs for')
  local str = args.pkg and M.pkgstr(obj) or M.docstr(obj)
  require'cxt.term'{str, to=require'asciicolor.style'.Styler{
    color=shim.color(args.color, require'fd'.isatty(io.stdout)),
  }}
end

M.shim = shim{help = 'doc help', exe = M.exe}

getmetatable(M).__call = function(_, args) return M.exe(args) end
return M

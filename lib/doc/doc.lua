local ERROR = [[
doc module requires global `mod` function/class, such as one of:

  require'pkg':install()
  mod = require'pkg'.mod

See lib/pkg/README.md for details
https://github.com/civboot/civlua/tree/main/lib/pkg

Note: also requires PKG_LOCSS and PKG_NAMES globals to be defined.
]]
-- Get documentation for lua types and stynatx.
-- Examples:
--    doc(string.find)
--    doc'for'
--    doc(myMod.myFunction)
local M = mod and mod'doc' or error(ERROR)
assert(PKG_LOCSS and PKG_NAMES, ERROR)

local mty  = require'metaty'
local ds   = require'ds'
local sfmt = string.format
local push = table.insert

--------------------
-- Global Functions

-- next(tbl, key) -> nextKey
-- Special:
--   key=nil      return first key in the table
--   key=lastKey  return nil
M.next = next -- from stdlib

--pcall(fn, ...inp): handle errors.
--  calls fn(...inp) and returns:
--    ok=false, error    for errors
--    ok=true, ...out    for success
M.pcall = pcall -- from stdlib

--select(index, ...inp) -> inp[index:]
--removes index-1 items from inp stack.
--If index='#' returns #inp.
M.select = select -- from stdlib

-- type(v) -> typeString. Possible values:
--
--   "nil" number string boolean table
--   function thread userdata
--
-- See also: metaty.ty(v) for metatypes
M.type = type -- from stdlib

-- setmetatable(t, mt) -> t
-- Sets the metatable on table which adds context (metatype)
-- as well as affects behavior of operators (metamethods)
--
--     t[k]     t[k]=v      NOTE: ONLY CALLED WHEN KEY
--     __index  __newindex        IS MISSING
--
--     +         -        *        /       //        %
--     __add     __sub    __mul    __div   __idiv    __mod
--               __unm
--
--     &         |        ~        <<      >>        ^
--     __band    __bor    __bnot   __shl   __shr     __pow
--
--     ==        <        <=       #        ..
--     __eq      __lt     __le     __len    __concat
--
--     t()       __tostring
--     __call    __name
--
-- metaty: __fields   __fmt
M.setmetatable = setmetatable -- from stdlib

--getmetatable(t) -> mt  See setmetatable.
M.getmetatable = getmetatable -- from stdlib

-------------------------------
-- string

-- string.find(subject:str, pat, index=1)
--  -> (starti, endi, ... match strings)
--
-- Find the pattern in the subject string, starting at the index.
--
-- assertEq({2, 4},       {find('%w+', ' bob is nice')})
-- assertEq({2, 7, 'is'}, {find(' bob is nice', '%w+ (%w+)')})
--
-- Character classes for matching specific sets:
--
--     .   all characters
--     %a  letters
--     %c  control characters
--     %d  digits
--     %l  lower case letters
--     %p  punctuation characters
--     %s  space characters
--     %u  upper case letters
--     %w  alphanumeric characters
--     %x  hexadecimal digits
--     %z  the character with representation 0
--
-- Magic characters, `.` indicates one character, more indicates many:
--
--     %.     selects a character class or escapes a magic char
--     (...)  create a group
--     [...]  create your own character class
--     [^..]  inversion of [...]
--     +.     match one or more of previous class  (NOT group)
--     *.     match zero or more of previous class (NOT group)
--     ?      match zero or one of previous class  (NOT group)
--     ^...   if at pat[1], match only beggining of text
--     ...$   if at pat[#pat], match only end of text
--
-- Also: %[1-9] refers to a the previously matched group
-- and matches it's exact content.
--
-- assert(    find('yes bob yes',  '(%w+) bob %1'))
-- assert(not find('yes bob no',   '(%w+) bob %1'))
M['string.find'] = string.find -- from stdlib

-- match(subj, pat, init) return the capture groups of pat
-- or the whole match if no capture groups.
--
-- See also: string.find.
M['string.match'] = string.match -- from stdlib


-- gmatch(subj, pat, init) match iterator function.
M['string.gmatch'] = string.gmatch -- from stdlib

-- substring by index (NOT pattern matching).
--
--   string.sub(subject: str, start: num, end: num) -> str[s:e]
--
-- Note: This is confusingly named considering string.gsub uses pattern
-- matching. Such is life.
M['string.sub'] = string.sub -- from stdlib

-- Globally Substittue pattern with subpattern.
--
--   string.gsub(subject: str, pat, subpat, index=1) -> str
--
-- Reference:
--   string.find for pattern documentation.
--
-- The subpattern has no special characters except:
--
--   %%     a literal %
--   %1-9   a matched group from pat
--
-- gsub = string.gsub
--   assertEq('yes ann yes',
--     gsub(  'yes bob yes', '(%w+) bob %1', '%1 ann %1'))
M['string.gsub'] = string.gsub -- from stdlib

-- Format values into a fmt string, i.e: format('%s: %i', 'age', 42)
--
-- string.format(fmt: str, ...) -> str
--
-- Examples:
--   sfmt = string.format
--   assertEq('age: 42',    sfmt('%s: %i',   'age', 42))
--   assertEq('age:    42', sfmt('%s: %5i',  'age', 42))
--   assertEq('age: 00042', sfmt('%s: %05i', 'age', 42)
--
-- Directives:
--
--   %%    literal % char
--   %d    decimal
--   %o    octal
--   %x    hexidecimal (%X uppercase)
--   %f    floating point
--   %s    string
--
-- Directive control structure:
--
--   % <fill character>? <fill count> directive
M['string.format'] = string.format -- from stdlib


-- string.byte(s [i, j]) -> number: get numberic code/s for s[i:j]
M['string.byte'] = string.byte -- from stdlib


-- char(c1, c2, ...) -> string
-- convert character codes to string and concatenate
M['string.char'] = string.char -- from stdlib

-- rep(s, n, sep) -> string -- repeat s n times with separator.
M['string.rep'] = string.rep -- from stdlib

-- pack(packfmt, ...values) -> string
-- pack the values into the string using the packfmt.
--
-- Packfmt:
--   <  >  =      little / big / native endian
--   ![n]         max alignment = n bytes
--   b B          signed / unsigned byte
--   h H l L      native short(h) and long(l) + unsigned vers
--   i[n] I[n]    signed/unsigned int with n bytes
--   f d          native float / double
--   T            size_t
--   c[n]         fixed-sized string of n bytes (unaligned)
--   z            zero-terminated string        (unaligned)
--   s[n]         counted string of size n count
--   x            one byte of padding
--   X[op]        align to option op, i.e. Xi4
--   j J n        lua Integer / Unsigned / Number
M['string.pack'] = string.pack -- from stdlib


-- unpack(fmt, str) -> ...
-- See string.pack for the fmt
M['string.unpack'] = string.unpack -- from stdlib

-- string.packsize(fmt) -> int
-- Get the size which is used by fmt.
M['string.packsize'] = string.packsize -- from stdlib

-------------------------------
-- table
-- concatenate values in a table.
--
--   table.concat(table, sep='')
--
-- assertEq(1..' = '..3, concat{1, ' = ', 3})
-- assertEq('1, 2, 3',   concat({1, 2, 3}, ', ')
M['table.concat'] = table.concat -- from stdlib

-- table.remove(table, index=#table) -> ()
-- remove an item from a table, returning it.
-- The table is shifted if index < #table.
M['table.remove'] = table.remove -- from stdlib

-- table.sort(list, function=nil) sort table in-place
M['table.sort'] = table.sort -- from stdlib

-- insert or add to table (list-like)
--
-- local t = {}
-- table.insert(t, 'd')    -- {'d'
-- table.insert(t, 'e')    -- {'d', 'e'}
-- table.insert(t, 'b', 1) -- {'b', 'd', 'e'}
-- table.insert(t, 'c', 2) -- {'b', 'c', 'd', 'e'}
--
-- Recommendation:
--   local add = table.insert; add(t, 4)
M['table.insert'] = table.insert -- from stdlib

-------------------------------
-- io module
-- Open -> do input and output -> close files.
--
-- Methods:
--   input(file=nil)  ->  file    get/set stdin
--   output(file=nil) ->  file    get/set stdout
--   tmpfile() -> file            note: removed on program exit
--   popen()   -> file            see io.popen
--   lines(path or file) -> iter  close when done, fail=error
--   type(f) -> "[closed ]file"   get whether f is a file
--
-- file object:
--   read(format="l")   read a file according to format
--   lines(format="l")  get iterator for reading format
--   write(a, b, ...)   write strings a, b, ... in order
--   flush()            flush (save) all writes
--   seek(whence, offset)
--   setvbuf("no|full|line", sizeHint=appropriateSize)
--
-- format (read, etc)                  (in Lua<=5.2)
--   a       read all text                        *a
--   l       read next line, skip EOL             *l
--   L       read next line, keep EOL             *L
--   n       read and return a number             *n
--   number  read an exact number of bytes, EOF=nil
--   0       EOF=nil, notEOF=''
--
-- seek
--   whence="set"  offset from beginning of file (0)
--   whence="cur"  offset from current position
--   whence="end"  offset from end of file (use negative)
--   seek()    ->  get current position
--   seek'set' ->  set to beginning
--   seek'end' ->  set to end
M.io = io -- from stdlib

-- Execute shell command in separate process.
--
-- io.popen(command, mode='r|w') -> file
--
-- Reference:
--   os.execute: docs on file:close()
--   civix.sh: ergonomic blocking shell.
--
-- Note: as of Lua5.4 it is not possible to have stderr or both stdin&stdout.
M['io.popen'] = io.popen -- from stdlib

-------------------------------
-- os module
--
-- Useful functions:
--   exit(rc=0, close=false) exit program with return code
--   date()                  get the date. See os.date
--   execute'command'        execute command, see os.execute
--   getenv(varname)         get environment variable
--   remove(path)            rm path
--   rename(old, new)        mv old new
--   tmpname() -> path       create temporary file
--   clock()                 seconds used by process (performance)
--
-- Recommendation:
--   civix.epoch() returns nanosec precision, os.time() only sec.
M.os = os -- from stdlib

-------------------------------
-- os.execute and io.popen
-- Execute shell command via C's `system` API.
--
--   os.execute'shell command' -> (ok, "exit", rc)
--   os.execute()              -> shellAvailable
--
-- Recommendation:
--   For all but the simplest cases use io.popen instead.
--
-- Args:
--    ok      true on command success, false if rc>0
--    "exit"  always literal "exit" if command completed
--    rc      the return code of the command
--
-- Prints:
--    prints whatever was executed. There are no ways to
--    redirect the output besides piping in the command
--    string itself.
M['os.execute'] = os.execute -- from stdlib

---------------------
-- Keywords

-- Note: non-keywords are not actually stored in this module
-- (their docs are preserved in SRC* globals)
for k, obj in pairs(M) do
  local name = PKG_NAMES[obj]; if name then
    local newname = name:sub(5)
    PKG_NAMES[obj] = newname
    PKG_LOOKUP[name] = nil; PKG_LOOKUP[newname] = obj
  end
end

-- for is a looping construct with two forms:
--
-- Numeric:
--   for: for i=si,ei,period do
--     -- code using [si -> ei] (inclusive) with period --
--   end
--
-- Generic:
--   for i, v, etc in explist do
--       -- code using a, b, etc here --
--   end
--
-- A Generic for destructures to:
--   do -- Note: $vars are not accessible
--     local $fn, $state, $index = explist
--     while true do
--       local i, v, etc = $f($state, $index)
--       if i == nil then break end
--       $index = i
--       -- code using i, v, etc here
--     end
--   end
--
-- The goal in writing a stateless iterator function is to match this
-- loop's API as much as possible. Note that $index and $state are
-- names reflecting how the variables are used for i/pairs.
--
-- Example rewriting ipairs:
--
--   local function rawipairs(t, i)
--     i = i + 1
--     if i > #t then return nil end
--     return i, t[i]
--   end
--
--   local function ipairs_(t)
--     return rawipairs, t, 0
--   end
--
-- Example rewriting pairs using next(t, key)
--
--   function pairs(t)
--     return next, t, nil
--   end
--
-- See also:
--   metaty.split is a more complex example.
M['for'] = function() end
PKG_LOOKUP['for'] = M['for']

-- local x = (expression)
--
-- Define a local (instead of a global) variable. Prefer local variables for
-- most things unless you are:
--
-- * modifying the fundamentals of the language (i.e. replacing 'require')
-- * implementing a "protocol" for libraries to communicate global state (i.e. LAP)
-- * managing true physical state (i.e. robotics, terminal output, etc)
-- * you are the top-level application (i.e. a game, CLI, etc) and global state
--   is the best solution.
M['local'] = function() end
PKG_LOOKUP['local'] = M['local']

---------------------
-- Doc and DocItem

local VALID = {['function']=true, table=true}
M.modinfo = function(obj)
  if type(obj) == 'function' then return mty.fninfo(obj) end
  local name, loc = PKG_NAMES[obj], PKG_LOCSS[obj]
  name = name or (type(obj) == 'table') and rawget(obj, '__name')
  return name, loc
end

M.findcode = function(loc) --> (comments, code)
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
    if not line:find'^%-%-' then
      table.move(lines, #code+1, l-1, 1, comments); break
    end
  end
  return ds.reverse(comments), ds.reverse(code)
end

-- Documentation on a single type
-- These pull together the various sources of documentation
-- from the PKG and META_TY specs into a single object.
--
-- Example: metaty.tostring(doc(myObj))
M.Doc = mty'Doc' {
  'name', 'ty [Type]: type, can be string',
  'path [str]',
  'fields [table]', 'other [table]',
}
M.DocItem = mty'DocItem' {
  'name', 'ty [string]', 'path [string]',
  'default [any]'
}

local function fmtItems(f, items, name)
  push(f, '\n## '..name); f:incIndent(); push(f, '\n')
  for i, item in ipairs(items) do
    push(f, item:__tostring());
    if i < #items then push(f, '\n') end
  end
  f:decIndent(); push(f, '\n')
end
local fmtAttrs = function(d, f)
  if d.fields and next(d.fields) then fmtItems(f, d.fields, 'Fields') end
  if d.other  and next(d.other)  then fmtItems(f, d.other, 'Methods, Etc') end
end

M.Doc.__fmt = function(d, f)
	push(f, d.name or '?')
  if d.ty   then push(f, sfmt(' [%s]', d.ty)) end
  if d.path then push(f, sfmt(' (%s)', d.path)) end
  fmtAttrs(d, f)
end

M.DocItem.__tostring = function(di)
  local ty = di.ty and (': '..mty.tyName(di.ty))
  local def = type(di.default) ~= 'nil' and mty.format(' = %q', di.default)
  ty = (ty or '')..(def or '')

  local path; if di.path then
    path = di.path:match'([^/]*/[^/]+:%d+)'
    path = path and sfmt('(%s)', path)
  end
  return string.format('%-16s%-20s%s',
    di.name or '?', ty or '', path or '')
end

getmetatable(M.Doc).__call = function(T, obj)
  local name, path = M.modinfo(obj)
  local d = mty.construct(T, {
    name=name, path=path,
    ty=mty.tyName(mty.ty(obj)),
  })
  if type(obj) ~= 'table' then return d end
  d.fields, d.other = {}, {}
  local fields = rawget(obj, '__fields')
  if fields then
    for _, field in ipairs(fields) do
      push(d.fields, M.DocItem{
        name=field, ty=fields[field], default=rawget(obj, field),
      })
    end
  end
  local other = ds.copy(obj)
  if fields then for k in pairs(other) do -- remove shared fields
    if fields[k] then other[k] = nil end
  end end
  other = ds.orderedKeys(other)
  for _, k in ipairs(other) do
    local v = obj[k]
    local ty = mty.ty(v)
    local _, vloc = M.modinfo(v)
    vloc = vloc and sfmt('[%s]', vloc) or nil
    push(d.other, M.DocItem {
      name=k, ty=v and mty.ty(v), path=select(2, M.modinfo(v)),
    })
  end
  return d
end

M.stripComments = function(com)
  if #com == 0 then return end
  local ind = com[1]:match'^%-%-(%s+)' or ''
  local pat = '^%-%-'..string.rep('%s?', #ind)..'(.*)%s*'
  for i, l in ipairs(com) do com[i] = l:match(pat) or l end
end
M.full = function(obj)
  if type(obj) == 'string' then obj = PKG_LOOKUP[obj] end
  local d = M.Doc(obj)
  local com, code = M.findcode(d.path)
  if not com then com, code = {}, {} end
  local f = mty.Fmt{}
  push(f, sfmt('## %s (%s) ty=%s\n', d.name, d.path or '?/?', d.ty or '?'))
  M.stripComments(com)
  for _, l in ipairs(com) do push(f, l); push(f, '\n') end
  fmtAttrs(d, f)
  if #code > 0 then push(f, '---- CODE ----\n') end
  for _, l in ipairs(code) do push(f, l); push(f, '\n') end
  return table.concat(f)
end

getmetatable(M).__call = function(_, obj) return M.full(obj) end
return M

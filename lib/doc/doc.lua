local pkg = require'pkglib'
local shim = require'shim'
local mty = require 'metaty'
local d = mty.docTy
local M = d({doc=mty.doc, docTy=mty.docTy}, [=[
Documentation and help for Lua types (including core).

   help 'string.find'

Register documentation for your own types with:

local myfunction = doc.doc[[my documentation]]
(function(... args ...)
  ... my implemntation ...
end)

Reference:
  metaty: create types. This re-exports metaty's
    doc, help and docTy
  https://www.lua.org/pil/contents.html  tutorial
  https://www.lua.org/manual/            reference manual

This module mainly exists to provide documentation on Lua's
core types. Recommended documentation is in the form:

module.function(arg1: ?type, arg2:type=default) -> returns

Notes:
  "?" denotes a nil, =value denotes a default. The args
  or return values can be replaced by "a|b" indicating a
  string of value "a" or "b" is used.

Note: The documentation in this module is brief by design.
For full documentation go to the links in Reference. This
documentation is for the civboot.org project and will
make small references to other civboot libraries.
]=])

---------------------
-- Keywords
M['for'] = [[
for is a looping construct with two forms:

Numeric:
  for: for i=si,ei,period do
    -- code using [si -> ei] (inclusive) with period --
  end

Generic:
  for i, v, etc in explist do
      -- code using a, b, etc here --
  end

A Generic for destructures to:
  do -- Note: $vars are not accessible
    local $fn, $state, $index = explist
    while true do
      local i, v, etc = $f($state, $index)
      if i == nil then break end
      $index = i
      -- code using i, v, etc here
    end
  end

The goal in writing a stateless iterator function is to match this
loop's API as much as possible. Note that $index and $state are
names reflecting how the variables are used for i/pairs.

Example rewriting ipairs:

  local function rawipairs(t, i)
    i = i + 1
    if i > #t then return nil end
    return i, t[i]
  end

  local function ipairs_(t)
    return rawipairs, t, 0
  end

Example rewriting pairs using next(t, key)

  function pairs(t)
    return next, t, nil
  end

See also:
  metaty.split is a more complex example.
]]

--------------------
-- Global Functions
d(next, [[next(tbl, key): return next key in table.
Special:
  key=nil      return first key in the table
  key=lastKey  return nil
]])

d(pcall, [[pcall(fn, ...inp): handle errors.
  calls fn(...inp) and returns:
    ok=false, error    for errors
    ok=true, ...out    for success]])

d(select, [[select(index, ...inp) -> inp[index:]
removes index-1 items from inp stack.
If index='#' returns #inp.]])

d(type, [[type(v) -> typeString. Possible values:

  "nil" number string boolean table
  function thread userdata

See also: metaty.ty(v) for metatypes]])

d(setmetatable, [[setmetatable(t, mt) -> t
Sets the metatable on table which adds context (metatype)
as well as affects behavior of operators (metamethods)

    t[k]     t[k]=v      NOTE: ONLY CALLED WHEN KEY
    __index  __newindex        IS MISSING

    +         -        *        /       //        %
    __add     __sub    __mul    __div   __idiv    __mod
              __unm

    &         |        ~        <<      >>        ^
    __band    __bor    __bnot   __shl   __shr     __pow

    ==        <        <=       #        ..
    __eq      __lt     __le     __len    __concat

    t()       __tostring
    __call    __name

metaty: __fields  __maybes  __missing  __fmt  __doc]])
d(getmetatable, [[getmetatable(t) -> mt  See setmetatable.]])

-------------------------------
-- string
d(string.find, [[
Find the pattern in the subject string, starting at the index.

  string.find(subject:str, pat, index=1)
   -> (starti, endi, ... match strings)

assertEq({2, 4},       {find('%w+', ' bob is nice')})
assertEq({2, 7, 'is'}, {find(' bob is nice', '%w+ (%w+)')})

Character classes for matching specific sets:

    .   all characters
    %a  letters
    %c  control characters
    %d  digits
    %l  lower case letters
    %p  punctuation characters
    %s  space characters
    %u  upper case letters
    %w  alphanumeric characters
    %x  hexadecimal digits
    %z  the character with representation 0

Magic characters, `.` indicates one character, more indicates many:

    %.     selects a character class or escapes a magic char
    (...)  create a group
    [...]  create your own character class
    [^..]  inversion of [...]
    +.     match one or more of previous class  (NOT group)
    *.     match zero or more of previous class (NOT group)
    ?      match zero or one of previous class  (NOT group)
    ^...   if at pat[1], match only beggining of text
    ...$   if at pat[#pat], match only end of text

Also: %[1-9] refers to a the previously matched group
and matches it's exact content.

assert(    find('yes bob yes',  '(%w+) bob %1'))
assert(not find('yes bob no',   '(%w+) bob %1'))
]])

d(string.match, [[match(subj, pat, init) return the capture groups of pat
or the whole match if no capture groups.

See also: string.find.]])

d(string.gmatch, [[gmatch(subj, pat, init) match iterator function.]])

d(string.sub, [[substring by index (NOT pattern matching).

  string.sub(subject: str, start: num, end: num) -> str[s:e]

Note: This is confusingly named considering string.gsub uses pattern
matching. Such is life.
]])

d(string.gsub, [[
Globally Substittue pattern with subpattern.

  string.gsub(subject: str, pat, subpat, index=1) -> str

Reference:
  string.find for pattern documentation.

The subpattern has no special characters except:

  %%     a literal %
  %1-9   a matched group from pat

gsub = string.gsub
  assertEq('yes ann yes',
    gsub(  'yes bob yes', '(%w+) bob %1', '%1 ann %1'))
]])

d(string.format, [[
Format values into a fmt string, i.e: format('%s: %i', 'age', 42)

string.format(fmt: str, ...) -> str

Examples:
  sfmt = string.format
  assertEq('age: 42',    sfmt('%s: %i',   'age', 42))
  assertEq('age:    42', sfmt('%s: %5i',  'age', 42))
  assertEq('age: 00042', sfmt('%s: %05i', 'age', 42)

Directives:

  %%    literal % char
  %d    decimal
  %o    octal
  %x    hexidecimal (%X uppercase)
  %f    floating point
  %s    string

Directive control structure:

  % <fill character>? <fill count> directive
]])

d(string.byte, [[byte(s [i, j]) -> number: get numberic code/s for s[i:j] ]])

d(string.char, [[char(c1, c2, ...) -> string
convert character codes to string and concatenate]])

d(string.rep, [[rep(s, n, sep) -> string -- repeat s n times with separator.]])

d(string.pack, [[pack(packfmt, ...values) -> string
pack the values into the string using the packfmt.

Packfmt:
  <  >  =      little / big / native endian
  ![n]         max alignment = n bytes
  b B          signed / unsigned byte
  h H l L      native short(h) and long(l) + unsigned vers
  i[n] I[n]    signed/unsigned int with n bytes
  f d          native float / double
  T            size_t
  c[n]         fixed-sized string of n bytes (unaligned)
  z            zero-terminated string        (unaligned)
  s[n]         counted string of size n count
  x            one byte of padding
  X[op]        align to option op, i.e. Xi4
  j J n        lua Integer / Unsigned / Number
]])

d(string.unpack, [[unpack(fmt, str) -> ...
See string.pack for the fmt.]])

d(string.packsize, [[string.packsize(fmt) -> int
Get the size which is used by fmt.]])

-------------------------------
-- table
d(table.concat, [[
concatenate values in a table.

  table.concat(table, sep='')

assertEq(1..' = '..3, concat{1, ' = ', 3})
assertEq('1, 2, 3',   concat({1, 2, 3}, ', ')
]])

d(table.remove, [[
remove an item from a table, returning it.

  table.remove(table, index=#table)

The table is shifted if index<#table.
]])

d(table.sort, 'table.sort(list, function=nil) sort table in-place')

d(table.insert, [[
insert or add to table (list-like)

local t = {}
table.insert(t, 'd')    -- {'d'
table.insert(t, 'e')    -- {'d', 'e'}
table.insert(t, 'b', 1) -- {'b', 'd', 'e'}
table.insert(t, 'c', 2) -- {'b', 'c', 'd', 'e'}

Recommendation:
  local add = table.insert; add(t, 4)
]])


-------------------------------
-- io module
d(io, [[
Open -> do input and output -> close files.

Methods:
  input()  ->  file            get stdin
  output() ->  file            get stdout
  tmpfile() -> file            removed on program exit
  popen()   -> file            see io.popen
  input (path or file)         set stdin
  output(path or file)         set stdout
  lines(path or file) -> iter  close when done, fail=error
  type() -> ?"file|closed file"

file object:
  read(format="l")   read a file according to format
  lines(format="l")  get iterator for reading format
  write(a, b, ...)   write strings a, b, ... in order
  flush()            flush (save) all writes
  seek(whence, offset)
  setvbuf("no|full|line", sizeHint=appropriateSize)

format (read, etc)                  (in Lua<=5.2)
  a       read all text                        *a
  l       read next line, skip EOL             *l
  L       read next line, keep EOL             *L
  n       read and return a number             *n
  number  read an exact number of bytes, EOF=nil
  0       nil=EOF, ''=notEOF

seek
  whence="set"  offset from beginning of file (0)
  whence="cur"  offset from current position
  whence="end"  offset from end of file (use negative)
  seek()    ->  get current position
  seek'set' ->  set to beginning
  seek'end' ->  set to end
]])
for k, v in pairs(io) do
  if type(v) == 'table' or type(v) == 'function' then
    d(v, 'See "io" for documentation')
  end
end

-------------------------------
-- os
d(os, [[os functions

Useful:
  exit(rc=0, close=false) exit program with return code
  date()                  get the date. See os.date
  execute'command'        execute command, see os.execute
  getenv(varname)         get environment variable
  remove(path)            rm path
  rename(old, new)        mv old new
  tmpname() -> path       create temporary file
  clock()                 seconds used by process (performance)

Recommendation:
  civix.epoch() returns nanosec precision, os.time() only sec.
]])
for k, v in pairs(os) do
  if type(v) == 'table' or type(v) == 'function' then
    d(v, 'See "os" for documentation')
  end
end

-------------------------------
-- os.execute and io.popen
d(os.execute, [[
Execute shell command via C's `system` API.

  os.execute'shell command' -> (ok, "exit", rc)
  os.execute()              -> shellAvailable

Recommendation:
  For all but the simplest cases use io.popen instead.

Args:
   ok      true on command success, false if rc>0
   "exit"  always literal "exit" if command completed
   rc      the return code of the command

Prints:
   prints whatever was executed. There are no ways to
   redirect the output besides piping in the command
   string itself.
]])

d(io.popen, [[
Execute shell command in separate process.

io.popen(command, mode='r|w') -> file

Reference:
  os.execute: docs on file:close()
  civix.sh: ergonomic blocking shell.

Note: as of Lua5.4 it is not possible to have stderr or both stdin&stdout.
]])


return M

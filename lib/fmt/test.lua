
local T = require'civtest'.Test
local CT = require'civtest'
local mty = require'metaty'
local M = require'fmt'
local fmt = M
local assertEq, assertMatch = T.eq, CT.assertMatch

T.tostring = function()
  assertEq('"a123"',    fmt("a123"))
  assertEq('"123"',     fmt("123"))
  assertEq('"abc def"', fmt("abc def"))
  assertEq('423',       fmt(423))
  assertEq('1A',        M.tostring(26, M.Fmt{numfmt='%X'}))
  assertEq('true',      fmt(true))
  assertMatch('fn"fmt.errorf"%[.*/fmt%.lua:%d+%]', fmt(M.errorf))
  assertMatch('{hi=4}', fmt{hi=4})
  assertMatch('{hi=4}',
    fmt(setmetatable({hi=4}, {}))
  )
end

T.fmt = function()
  assertEq("{1, 2, 3}", M.tostring{1, 2, 3})

  local t = {1, 2}; t[3] = t
  assertMatch('{!max depth reached!}',    M.tostring(t))

  assertEq( [[{baz="boo", foo="bar"}]],
    M.tostring{foo="bar", baz="boo"})
  local result = M.tostring({a=1, b=2, c=3}, M.Fmt:pretty{})
  assertEq('{\n  a=1,\n  b=2,\n  c=3\n}', result)
  assertEq('{1, 2, a=12}', M.tostring{1, 2, a=12})
  assertEq('{["a b"]=5}', M.tostring{['a b'] = 5})
  assertEq('{\n  1, 2, \n  a=12\n}',
           M.tostring({1, 2, a=12}, M.Fmt:pretty{}))
end

T.format = function()
  assertEq('hi "Bob"! Goodbye',
    M.format('hi %q! %s', 'Bob', 'Goodbye'))
  assertEq('running point: {x=3, y=7}...',
    M.format('%s point: %q...', 'running', {x=3, y=7}))
end

T.record = function()
  local A = mty'A'{'a2[any]', 'a1[any]'}
  local B = mty'B'{
    'b1[number]', 'b2[number] (default=32)',
    'a[A]'
  }
  assertEq('A{a2=5, a1="hi"}', fmt(A{a1='hi', a2=5}))
  assertEq('B{b1=5, b2=7, a=A{a2=4, a1="hi"}}', fmt(B{
    b1=5, b2=7, a=A{a1='hi', a2=4},
  }))
end

T.binary = function()
  local bin = require'fmt.binary'
  local format = function(...)
    local f = M.Fmt{}; bin.format(f, ...); return table.concat(f)
  end

  T.eq("68 65 6c 6c 6f ", format('hello'))
  T.eq("68 00 6c fa 6f ", format('h\0l\xFAo'))
  T.eq(
"     0: 68 69 20 74  | hi t\
     4: 68 65 72 65  | here\
     8: 20 62 6f 62  |  bob\
    12: 21           | !"
  , bin('hi there bob!', 4))
  T.eq(
"     0: 68 69        | hi", bin('hi', 4))
end

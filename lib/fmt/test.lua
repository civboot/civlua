
local T = require'civtest'
local M = require'fmt'

local test, assertEq, assertMatch = T.test, T.assertEq, T.assertMatch
local str = M.tostring

test("tostring", function()
  assertEq('"a123"',    str("a123"))
  assertEq('"123"',     str("123"))
  assertEq('"abc def"', str("abc def"))
  assertEq('423',       str(423))
  assertEq('1A',        str(26, M.Fmt{numfmt='%X'}))
  assertEq('true',      str(true))
  assertMatch('fn"fmt.errorf"%[.*/fmt%.lua:%d+%]', str(M.errorf))
  assertMatch('{hi=4}', str{hi=4})
  assertMatch('{hi=4}',
    str(setmetatable({hi=4}, {}))
  )
end)

test("fmt", function()
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
end)

test('format', function()
  assertEq('hi "Bob"! Goodbye',
    M.format('hi %q! %s', 'Bob', 'Goodbye'))
  assertEq('running point: {x=3, y=7}...',
    M.format('%s point: %q...', 'running', {x=3, y=7}))
end)

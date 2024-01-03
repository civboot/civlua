METATY_CHECK = true

local push = table.insert
local mty = require'metaty'
local ds = require'ds'

local test, assertEq; mty.lrequire'civtest'

local M = require'tso'

local function l2str(t) return table.concat(t, '\n') end
local function serialize(t)
end
local function assertRow(expected, row)
  local ser = M.Ser{}; ser:row(row);
  push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))

  mty.pnt('?? -------- Deserializing')
  local de = M.De{ser.dat}
  local resRow = de()
  assertEq(row, resRow)
  assertEq(nil, de())
end
local function assertRows(expected, rows, headers, only)
  local ser, de
  if not only or only == 'ser' then
    ser = M.Ser{}
    if headers then for _, header in ipairs(headers) do
      if header then ser:header(header) else ser:clearHeader() end
    end
    end
    ser:rows(rows, header); push(ser.dat, '')
    assertEq(expected, l2str(ser.dat))
  end

  if not only or only == 'de' then
    de = M.De{ds.lines(expected)}
    local resRows = {}; for r in de do push(resRows, r) end
    assertEq(rows, resRows)
  end
  return ser, de
end

test('step_by_step', function()
  local ser = M.Ser{dat=out or {}}
  local expected = '2\t3\t"hi there\t5'
  ser:any(2); ser:any(3); ser:any'hi there'; ser:any(5)
  ser:finishLine()
  assertEq(expected, l2str(ser.dat))
  assertRow(expected..'\n', {2, 3, 'hi there', 5})

  local expected = [[
"table	{1	2	}
]]
  local ser = M.Ser{dat=out or {}}
  ser:any'table'; ser:table{1, 2}
  ser:finishLine(); push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
  assertRow(expected, {'table', {1, 2}})

  local expected = [[
"nested	{
  1	2
  3	4
}5	6
]]
  local ser = M.Ser{dat=out or {}}
  local row = {'nested', {{1, 2}, {3, 4}}, 5, 6}
  ser:tableRow(row)
  ser:finishLine(); push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
  assertRow(expected, row)
end)

test('singles', function()
  assertRows('1\t2\t"hi\n', {{1, 2, "hi"}})
  assertRow('.foo\t"bar\n', {foo='bar'})
end)

test('nested', function()
  assertRow([[
.accounts	{
  1	1000	"savings
  1	100	"checking
  2	120	"checking
}
+.users	{
  1	"John	"1999-10-31
  +.notes	{"bit mean	"tips well	}
  2	"Maxine	"1998-12-25
  +.notes	{"very nice	}
}
]],
  {
    accounts = {
      {1, 1000, "savings"},
      {1, 100,  "checking"},
      {2, 120,  "checking"},
    },
    users = {
      {1, "John", "1999-10-31", notes={"bit mean", "tips well"}},
      {2, "Maxine", "1998-12-25", notes={"very nice"}},
    },
  }
)
end)

test('header', function()
  assertRows([[
#"a	"b	"c
1	"hi	2
3	"bye	4
5	{"inner	6	}7
]], {
    {a=1, b="hi",  c=2},
    {a=3, b="bye", c=4},
    {a=5, b={"inner", 6}, c=7},
  }, --[[headers]] {{"a", "b", "c"}})
end)

test('nested header', function()
  assertRows([[
.nested	{
  #"a	"b	"c
  1	"hi	2
  3	"bye	4
}
]], {
    { nested = {
        [M.HEADER] = {'a', 'b', 'c'},
        {a=1, b="hi",  c=2},
        {a=3, b="bye", c=4},
      }
    },
  })
end)

test('multi keyed', function()
  assertRows([[
.a	1000
+.i	1
+.t	"savings
.a	100
+.i	1
+.t	"checking
.a	120
+.i	2
+.t	"checking
]], {
      {i=1, a=1000, t="savings"},
      {i=1, a=100,  t="checking"},
      {i=2, a=120,  t="checking"},
    })
end)

test('named header', function()
  local root = {name='root', 'a', 'b', 't'}
  assertRows([[
#root	"a	"b	"t
1	2	{3	}
]], {
    {a=1, b=2, t={3},}
  }, {root})

  local inner = {name='inner', 'c', 'd'}
  assertRows([[
#root	"a	"b	"t
1	2	{
  #inner	"c	"d
  3	4
}
5	6	{
  #inner
  7	8
  9	10
}
]], {
    {a=1, b=2, t={
      [M.HEADER]=inner,
      {c=3, d=4},
    }},
    {a=5, b=6, t={
      [M.HEADER]=inner,
      {c=7, d=8},
      {c=9, d=10},
    }},
  }, {root})

  local user = {name='user', 'n', 'b'}
  local account = {name='account', 'i', 'a', 't'}
  local ser, de = assertRows([[
#user	"n	"b
#account	"i	"a	"t
#
.accounts	{
  #account
  1	1000	"savings
  1	100	"checking
  2	120	"checking
}
+.users	{
  #user
  "John	"1999-10-31
  "Maxine	"1998-12-25
}
]], {
    {
      accounts = {
        [M.HEADER] = account,
        {i=1, a=1000, t="savings"},
        {i=1, a=100,  t="checking"},
        {i=2, a=120,  t="checking"},
      },
      users = {
        [M.HEADER] = user,
        {n="John",   b="1999-10-31"},
        {n="Maxine", b="1998-12-25"},
      },
    },
  }, {user, account, false})
  assertEq({user=user, account=account}, de.headers)

end)

test('mixed rows', function()
  assertRows([[
1	2	{
  3	4
 *5	}
]], {
  {1, 2, {{3, 4}, 5}}
})
end)

test('multi key newlines', function()
  assertRows([[
1	2
+.key1	1
+.key2	22
]], {
  {1, 2, key1=1, key2=22},
})
end)

test('comment', function()
  assertRows([[
#"a	"b	-- unused, testing comment
#"c	"d	-- used
1	2	    -- just a comment
"three	"four	--another comment


-- above and below, empty lines
--



]], {
  {c=1,       d=2},
  {c='three', d='four'},
}, nil, 'de')
end)

test('attrs', function()
  local expect = [[
@name	"testname
@doc	"the doc
#"a	"b
10	20
@ibase	16
$10	$20
]]
  local ser = M.Ser{}
  ser:attr('name', 'testname')
  ser:attr('doc', 'the doc')
  local header = {'a', 'b'}
  ser:header(header)
  ser:row({a=10,   b=20}, header)
  ser:attr('ibase', 16)
  ser:row({a=0x10, b=0x20}, header)
  push(ser.dat, '')
  assertEq(expect, l2str(ser.dat))

  local de = M.De{ds.lines(expect)}
  local result = {}; for r in de do push(result, r) end
  assertEq({
    {a=10, b=20},
    {a=0x10, b=0x20},
  }, result)
end)

-- TODO: test multiline strings and attributes

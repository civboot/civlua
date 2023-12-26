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
local function assertRows(expected, rows, header)
  local ser = M.Ser{}; ser:rows(rows, header)
  push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))

  if true then -- not header then
    mty.pnt('?? -------- Deserializing')
    local de = M.De{ser.dat}
    local resRows = {}; for r in de do push(resRows, r) end
    assertEq(rows, resRows)
  end
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
}.users	{
  1	"John	"1999-10-31	.notes	{"bit mean	"tips well	}
  2	"Maxine	"1998-12-25	.notes	{"very nice	}
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
  }, --[[header]] {"a", "b", "c"})
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

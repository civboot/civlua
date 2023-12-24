METATY_CHECK = true

local push = table.insert
local mty = require'metaty'
local ds = require'ds'

local test, assertEq; mty.lrequire'civtest'

local M = require'tso'

local function l2str(t) return table.concat(t, '\n') end
local function serialize(t)
end
local function assertRow(expected, row, chkDe)
  local ser = M.Ser{}; ser:row(row);
  push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))

  if chkDe then
    local de = M.De{ser.dat}
    local resRow = de()
    assertEq(row, resRow)
    assertEq(nil, de())
  end
end
local function assertRows(expected, rows)
  local ser = M.Ser{}; ser:rows(rows);
  push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
end

test('basic', function()
  local ser = M.Ser{dat=out or {}}
  local expected = '2\t3\t"hi there\t5'
  ser:any(2); ser:any(3); ser:any'hi there'; ser:any(5)
  ser:finishLine()
  assertEq(expected, l2str(ser.dat))
  assertRow(expected..'\n', {2, 3, 'hi there', 5}, true)

  local expected = [[
"table	{1	2	}
]]
  local ser = M.Ser{dat=out or {}}
  ser:any'table'; ser:any{1, 2}
  ser:finishLine(); push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
  assertRow(expected, {'table', {1, 2}}, true)

  local expected = [[
"nested	{
  1	2
  3	4
}5	6
]]
  local ser = M.Ser{dat=out or {}}
  local row = {'nested', {{1, 2}, {3, 4}}, 5, 6}
  ser:any(row, true)
  ser:finishLine(); push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
  assertRow(expected, row, true)
end)

test('nested', function()
  assertRows('1\t2\t"hi\n', {{1, 2, "hi"}})
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

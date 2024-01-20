METATY_CHECK = true

local push = table.insert
local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'

local test, assertEq; pkg.auto'civtest'

local M = pkg'tso'

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
local function assertRows(expected, rows, specs, only)
  local ser, de, specMap
  if specs then specMap = {}
    for _, s in ipairs(specs) do specMap[s.__name] = s end
  end
  if not only or only == 'ser' then
    ser = M.Ser{}
    if specs then for _, spec in ipairs(specs) do
      ser:spec(spec)
    end end
    mty.pnt('?? test specs', specs, ser.specs)
    ser:rows(rows); push(ser.dat, '')
    assertEq(expected, l2str(ser.dat))
    specs = ser.specs
  end

  if not only or only == 'de' then
    mty.pnt('?? test de specs', specs, specMap)
    de = M.De{ds.lines(expected), specs=specMap}
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

local Abc = mty.record'Abc':field'a' :field'b' :field'c'

test('header', function()
  assertRows([[
!Abc	"a	"b	"c
#Abc
1	"hi	2
3	"bye	4
5	{"inner	6	}7
]], {
    Abc{a=1, b="hi",  c=2},
    Abc{a=3, b="bye", c=4},
    Abc{a=5, b={"inner", 6}, c=7},
  }, {Abc})
end)

test('nested header', function()
  assertRows([[
!Abc	"a	"b	"c
.nested	{
  #Abc
  1	"hi	2
  3	"bye	4
}
]], {
    { nested = {
        Abc{a=1, b="hi",  c=2},
        Abc{a=3, b="bye", c=4},
      }
    },
  }, {Abc})
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

local Abt = mty.record'Abt':field'a' :field'b' :field't'
local Cd  = mty.record'Cd' :field'c' :field'd'
local User = mty.record'User':field'n' :field'b'
local Account = mty.record'Account'
  :field'i' :field'a' :field't'

test('named header', function()
  assertRows([[
!Abt	"a	"b	"t
#Abt
1	2	{3	}
]], {
    Abt{a=1, b=2, t={3},}
  }, {Abt})

  assertRows([[
!Abt	"a	"b	"t
!Cd	"c	"d
#Abt
1	2	{
  #Cd
  3	4
}
5	6	{
  #Cd
  7	8
  9	10
}
]], {
    Abt{a=1, b=2, t={
      Cd{c=3, d=4},
    }},
    Abt{a=5, b=6, t={
      Cd{c=7, d=8},
      Cd{c=9, d=10},
    }},
  }, {Abt, Cd})

  local user = {name='user', 'n', 'b'}
  local account = {name='account', 'i', 'a', 't'}
  local ser, de = assertRows([[
!User	"n	"b
!Account	"i	"a	"t
.accounts	{
  #Account
  1	1000	"savings
  1	100	"checking
  2	120	"checking
}
+.users	{
  #User
  "John	"1999-10-31
  "Maxine	"1998-12-25
}
]], {
    {
      accounts = {
        Account{i=1, a=1000, t="savings"},
        Account{i=1, a=100,  t="checking"},
        Account{i=2, a=120,  t="checking"},
      },
      users = {
        User{n="John",   b="1999-10-31"},
        User{n="Maxine", b="1998-12-25"},
      },
    },
  }, {User, Account})
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
!Cd	"c	"d	-- used
#Cd
1	2	    -- just a comment
"three	"four	--another comment


-- above and below, empty lines
--



]], {
  Cd{c=1,       d=2},
  Cd{c='three', d='four'},
}, {Cd}, 'de')
end)

test('attrs', function()
  local expect = [[
@name	"testname
@doc	"the doc
!Abc	"a	"b	"c
#Abc
10	20	30
@ibase	16
$10	$20	$30
]]
  local ser = M.Ser{}
  ser:attr('name', 'testname')
  ser:attr('doc', 'the doc')
  ser:spec(Abc)
  ser:row(Abc{a=10,   b=20,   c=30})
  ser:attr('ibase', 16)
  ser:row(Abc{a=0x10, b=0x20, c=0x30})
  push(ser.dat, '')
  assertEq(expect, l2str(ser.dat))

  local de = M.De{ds.lines(expect), specs={Abc=Abc}}
  local result = {}; for r in de do push(result, r) end
  assertEq({
    Abc{a=10,   b=20,   c=30},
    Abc{a=0x10, b=0x20, c=0x30},
  }, result)
end)

test('multiline', function()
  local ser, de = assertRows([[
1	"hi
'this is
'a multiline string	2
]], {
  {1, "hi\nthis is\na multiline string", 2},
})
end)

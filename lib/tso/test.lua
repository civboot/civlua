METATY_CHECK = true

local push = table.insert
local mty = require'metaty'
local ds = require'ds'
local lines = require'ds.lines'

local test, assertEq; ds.auto'civtest'

local M = require'tso'

local function l2str(t) return table.concat(t, '\n') end
local function serialize(t)
end
local function assertRow(expected, row)
  local ser = M.Ser{}; ser:row(row);
  push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))

  local de = M.De{ser.dat}
  local resRow = de()
  assertEq(row, resRow)
  assertEq(nil, de())
end
local function assertRows(expected, rows, specs, only)
  local ser, de
  if not only or only == 'ser' then
    ser = M.Ser{}
    if specs then for _, spec in ipairs(specs) do
      ser:define(spec)
    end end
    ser:rows(rows); push(ser.dat, '')
    assertEq(expected, l2str(ser.dat))
  end

  if not only or only == 'de' then
    de = M.De{lines(expected), specs=specs}
    assertEq(rows, de:all())
  end
  return ser, de
end

test('step_by_step', function()
  local ser = M.Ser{dat=out or {}}
  local expected = '2\t3\t"hi there\t5'
  ser:any(2); ser:any(3); ser:any'hi there'; ser:any(5)
  ser:_finishLine()
  assertEq(expected, l2str(ser.dat))
  assertRow(expected..'\n', {2, 3, 'hi there', 5})

  local expected = [[
"table	{1	2	}
]]
  local ser = M.Ser{dat=out or {}}
  ser:any'table'; ser:table{1, 2}
  ser:_finishLine(); push(ser.dat, '')
  assertEq(expected, l2str(ser.dat))
  assertRow(expected, {'table', {1, 2}})

local comments = '; some line\n; comments\n'
  local expected = [[
"nested	{
  1	2
  3	4
}5	6
]]
  local ser = M.Ser{dat=out or {}}
  ser:comment'some line\ncomments'
  local row = {'nested', {{1, 2}, {3, 4}}, 5, 6}
  ser:_tableRow(row)
  ser:_finishLine(); push(ser.dat, '')
  assertEq(comments..expected, l2str(ser.dat))
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

local Abc = mty'Abc'{'a', 'b', 'c'}

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

local Abt = mty'Abt'{'a', 'b', 't'}
local Cd  = mty'Cd'{'c', 'd'}
local User = mty'User'{'n', 'b'}
local Account = mty'Account'
  {'i', 'a', 't'}

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
!Cd	"c	"d	; used
#Cd
1	2	    ; just a comment
"three	"four	;another comment


; above and below, empty lines
;



]], {
  Cd{c=1,       d=2},
  Cd{c='three', d='four'},
}, {Cd}, 'de')
end)

test('autospec', function()
  local de = M.De{lines[[
  !0	"a	"b
  !1	"c	"d
  #0
  1	2 3 4
  "five	{:1	"six	"seven	}
  ]]}
  local res = de:all()
  local t0 = assert(de.specs['0'])
  local t1 = assert(de.specs['1'])
  assertEq('!0', t0.__name)
  assertEq({'a', 'b', a=true, b=true}, t0.__fields)
  assertEq({
    t0{a=1, b=2, 3, 4},
    t0{a='five', b = t1{
      c='six', d='seven',
    }},
  }, res)

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
  ser:define(Abc)
  ser:row(Abc{a=10,   b=20,   c=30})
  ser:attr('ibase', 16)
  ser:row(Abc{a=0x10, b=0x20, c=0x30})
  push(ser.dat, '')
  assertEq(expect, l2str(ser.dat))

  local de = M.De{lines(expect), specs={Abc=Abc}}
  assertEq({
    Abc{a=10,   b=20,   c=30},
    Abc{a=0x10, b=0x20, c=0x30},
  }, de:all())
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

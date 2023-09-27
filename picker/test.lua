-- FIXME: this file is not actually being run

local expectDisplay = trim[[
===========+==================+=======================+========================
date       | title            | text                  | todo
===========+==================+=======================+========================
2023-04-03 | "Good day today" | "This was a good day. | false
           |                  | The sun was shining." | 
 -  -  -   +  -  -  -  -  -   +  -  -  -  -  -  -  -  +  -  -  -  -  -  -  -   
" 04-05 "  | "Bad day"        | "Terrible day         | + 1="I don't know"
           |                  | Just terrible okay?." | + 2="have a better day"
 -  -  -   +  -  -  -  -  -   +  -  -  -  -  -  -  -  +  -  -  -  -  -  -  -
]]
test('display', nil, function()
  -- test trim
  assertEq('foo bar', trim('\n  \nfoo bar \n'))

  -- test lines function
  local l = List.fromIterV(lines("hi there\nbob\n"))
  assertEq(List{"hi there", "bob", ""}, l)
  -- split function
  local l = List.fromIterV(split("hi there\nbob\n"))
  assertEq(List{"hi", "there", "bob"}, l)

  -- test split function

  -- fillBuf
  local b = List{}; fillBuf(b, 5)
  assertEq(List{'   ', ' ', ' '}, b)

  local J = struct('Journal', {
    'date', 'title', 'text', 'todo'
  })
  local j = List{
    J{date='2023-04-03', title='Good day today',
      text='This was a good day.\nThe sun was shining.'},
    J{date=' 04-05 ', title='Bad day',
      text='Terrible day\nJust terrible okay?.',
      todo=List{"I don't know", 'have a better day'},
    },
  }
  local disp = Display(J, j:iterFn())
  local result = trim(tostring(disp))
  assertEq(expectDisplay, result)
end)

test('picker', nil, function()
  local A, B = structs()
  local lA = List{
    A{a1='one',   a2=1},
    A{a1='two',   a2=2},
    A{a1='three', a2=3},
  }
  local pA = Picker(A, lA)
  local result = pA.q.a1:eq('one')
  result = result:toList()
  assertEq(List{
    A{a1='one',   a2=1},
  }, result)

  assertEq(List{
    A{a1='one',   a2=1},
  }, pA.q.a1:eq('one'):toList())

  result = pA.q.a2:in_{2, 3}:toList()
  assertEq(List{
    A{a1='two',   a2=2},
    A{a1='three', a2=3},
  }, result)
  local q = (pA.q.a2:in_{2, 3}
                 .a1:eq('two'))
  -- TODO: we must
  --   1. support MULTIPLE indexes simultaniously
  --   2. support the iterator... somehow
  --
  -- I think this was very much an MVP and needs a lot more love to
  -- actually be useable :D
  --
  -- pnt(q:debug())
  -- assertEq(List{
  --   A{a1='two',   a2=2},
  -- }, q:toList())

  local G1 = genStruct('G1', {'a', Num, 'b', Str})
  assertEq('G1{a:Num b:Str}', tostring(G1))
  assert(rawequal(G1, genStruct('G1', {'a', Num, 'b', Str})))

  local g1 = G1{a=8, b='hel'}
  assert('G1{a=8 b=hel}', tostring(g1))

  local G2 = genStruct('G2', {'a', true, 'b', Str})
  assert(not rawequal(G1, G2))
  assertEq('G2{a:Any b:Str}', tostring(G2))

  result = pA.q.a2:in_{2, 3}:select{'a1'}
  local b = {}; fmtTableRaw(b, result, orderedKeys(result))
  assertEq('[Q{a1=two} Q{a1=three}]', tostring(result:toList()))

  local lB = List{
    B{b1=3,  b2=1},
    B{b1=5,  b2=2},
    B{b1=7,  b2=3},
  }
  local pB = Picker(B, lB)
  local result = pA.q:joinEq('a2', pB, 'b1')
  assertEq(
    '[joinEq{j1=A{a2=3 a1=three} j2=B{b1=3 b2=1 a=false}}]',
    tostring(result.data))
  local sel = result.q:select{'j1.a1', 'j2.b2'}:toList()
  assertEq('[Q{a1=three b2=1}]', tostring(sel))

  local result = Display(ty(sel[1]), sel:iterFn())
  local expected = trim[[
======+===
a1    | b2
======+===
three | 1
 -    +
]]
  assertEq(expected, trim(tostring(result)))

end)

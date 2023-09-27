METATY_CHECK = true

local mty = require'metaty'
local test, assertEq; mty.lrequire'civtest'

-- test('load', nil, function() mod = require('civ.sh') end)

local posix = require'posix'
local civix  = require'civix'

-- local sh, shCmd, assertSh = mod.sh, mod.shCmd, mod.assertSh

test('fork', function()
  local fork = civix.Fork(true, true)
  local p = fork.pipes
  assert(not p.lr and not p.lw)
  if not fork.isParent then
    local got, err =  p.r:read('a')
    assertEq(nil, err)
    io.stderr:write('child heard: ', tostring(got), tostring(err), '\n')
    io.stdout:write('I heard: '..got)
    p:close()
    os.exit(42)
  end
  p.w:write('to my child');  p.w:close()
  local got, err = p.r:read('a');
  assertEq(nil, err)
  assertEq('I heard: to my child', got)
  print('closing:', p.r:close())
  assert(fork:wait())
end)

test('exec', function()
  local fork = civix.Fork(true)
  local p = fork.pipes
  assert(not (p.lr or p.lw))
  if not fork.isParent then
    assert(not p.r)
    print("Child executing")
    io.stderr:write'Child executing (stderr)\n'
    fork:exec([[
      SANTA='Santa Clause'; echo "Hi I am $SANTA, ho ho ho"
    ]])
  end
  assert(not p.w)
  local got, err = p.r:read('a')
  assertEq(nil, err)
  assertEq('Child executing\nHi I am Santa Clause, ho ho ho\n',
           got)
  assert(fork:wait())
end)

-- local EMBEDDED = [[
--  echo $(cat << __LUA_EOF__
-- foo
-- bar
-- 
-- __LUA_EOF__
-- ) ]]

-- test('embedded', nil, function()
--   assertEq(EMBEDDED, mod.embedded('foo\nbar\n'))
-- end)

-- test('sh', nil, function()
--   assertEq('on stdout\n', sh[[ echo 'on' stdout ]].out)
--   assertEq(''           , sh[[ echo '<stderr from test>' 1>&2 ]].out)
--   local result = sh('false', {check=false})
--   assertEq(1, result.rc)
-- 
--   result = sh([[ echo '<stderr from test>' 1>&2 ]],
--               {err=true})
--   assert('<stderr from test>', result.err)
-- 
--   local cmd = {'echo', foo='bar'}
--   assertEq("echo --foo='bar'", shCmd{'echo', foo='bar'})
--   assertEq('--foo=bar\n'  ,  sh{'echo', foo='bar'}.out)
--   assert(select(3, shCmd{foo="that's bad"})) -- assert error
--   assertEq('from pipe', sh([[ cat ]], {inp='from pipe'}).out)
-- end)

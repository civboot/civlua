
local T = require'civtest'
local M = require'ele.keys'

local push = table.insert

local actions = {insert=true}

local events = function()
  local e = {}; return e, function(v) push(e, v) end
end

T.test('keypath', function()
  T.assertEq({'space', 'a', 'b'}, M.keypath'space a b')
end)

local function assertKeys(keyinputs, keys, expectKeys, expectEvents)
  local data = {
    bindings = M.bindings,
    actions = actions,
  }
  data.keys = type(keys) == 'string' and M.Keys{mode=keys}
           or assert(keys)
  local events = {}; local evsend = function(v) push(events, v) end
  for _, ki in ipairs(M.keypath(keyinputs)) do
    M.action(data, {action='keyinput', keyinput=ki}, evsend)
  end

  if expectKeys == false then T.assertEq(nil, data.keys.keep)
  elseif expectKeys then T.assertEq(expectKeys, data.keys) end
  T.assertEq(expectEvents or {}, events)
  return data.keys
end

T.test('action', function()
  local modes, k = M.bindings.modes
  -- Switch between modes
  k = assertKeys('esc',   'insert', false)
    T.assertEq('command', k.mode)
    T.assertEq({'esc'},   k.chord)
  k = assertKeys('i',     'command', false)
    T.assertEq('insert', k.mode)
    T.assertEq({'i'},    k.chord)
  k = assertKeys('esc i', 'insert', false)
    T.assertEq('command', k.mode)
    T.assertEq({'i'},     k.chord)

  -- Insert mode
  local ich = function(ch)
    return {action='insertChord', chord=M.keypath(ch)}
  end
  k = assertKeys('a', 'insert', false, {ich'a'})
    T.assertEq({'a'}, k.chord)
  k = assertKeys('space a', 'insert', false, {ich'space', ich'a'})
    T.assertEq({'a'}, k.chord)
end)


local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local lap = require'lap'
local M = require'ele.bindings'
local et = require'ele.types'
local keyinput = require'ele.actions'.keyinput

local push = table.insert

local actions = {insert=ds.noop, move=ds.noop, remove=ds.noop}

local events = function()
  local e = {}; return e, function(v) push(e, v) end
end

T.test('chords', function()
  T.assertEq({'space', 'a', 'b'}, M.chord'space a b')

  T.assertEq('a b', M.chordstr{'a', 'space', 'b'})
  T.assertEq('x',   M.chordstr{'x'})
end)

local function newData(keys)
  local data = {actions = actions}
  M.install(data)
  data.keys = type(keys) == 'string' and M.Keys{mode=keys}
           or assert(keys)
  return data
end
T.test('bindings', function()
  local data = newData'insert'
  et.checkBindings(M.insert)
  et.checkBindings(M.command)
end)

local function assertKeys(keyinputs, keys, expectKeys, expectEvents)
  local data = newData(keys)
  local events = lap.Recv(); local evsend = events:sender()
  for _, ki in ipairs(M.chord(keyinputs)) do
    keyinput(data, {action='keyinput', ki}, evsend)
  end

  if expectKeys == false then T.assertEq(nil, data.keys.keep)
  elseif expectKeys then T.assertEq(expectKeys, data.keys) end
  T.assertEq(expectEvents or {}, events:drain())
  return data.keys
end

T.test('action', function()
  local k
  -- Switch between modes
  k = assertKeys('esc',   'insert', false)
    T.assertEq('command', k.mode)
    T.assertEq({'esc'},   k.chord)
  k = assertKeys('i',     'command', false)
    T.assertEq('insert', k.mode)
    T.assertEq({'i'},    k.chord)
  mty.eprint('?? esc i')
  k = assertKeys('esc i', 'insert', false)
    T.assertEq('insert', k.mode)
    T.assertEq({'i'},     k.chord)

  -- Insert mode
  local ins = function(str) return {action='insert', str} end
  k = assertKeys('a', 'insert', false, {ins'a'})
    T.assertEq({'a'}, k.chord)
  k = assertKeys('space a', 'insert', false,
    {ins'a', ins' '}) -- note: reverse order because pushLeft
    T.assertEq({'a'}, k.chord)

  -- move
  local move = function(t) t.action = 'move'; return t end
  assertKeys('l',     'command', false, {move{off=1}})
  assertKeys('3 l',   'command', false, {move{off=1, times=3}})
  assertKeys('3 0 l', 'command', false, {move{off=1, times=30}})

  -- remove
  local rm = function(t) t.action = 'remove'; return t end
  assertKeys('d l',   'command', false, {rm{off=1}})
  assertKeys('5 d l', 'command', false, {rm{off=1,  times=5}})
  assertKeys('3 d d', 'command', false, {rm{lines=0, times=3}})

  local ch = function(t) t.mode = 'insert'; return rm(t) end
  k = assertKeys('3 c l', 'command', false, {ch{off=1, times=3}})
    T.assertEq('insert', k.mode)
  assertKeys('c c',   'command', false, {ch{lines=0}})
    T.assertEq('insert', k.mode)

  -- find
  assertKeys('f x',       'command', false,
    {move{find='x', move='find'}})
  assertKeys('1 0 d f x', 'command', false,
    {  rm{find='x', move='find', times=10}})
  assertKeys('1 0 d t x', 'command', false,
    {  rm{find='x', move='find', times=10, cols=-1}})

  -- Event
  assertKeys('I', 'command', false, {move{move='sol', mode='insert'}})
end)

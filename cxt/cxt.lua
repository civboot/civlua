
local mty = require'metaty'
local ds  = require'ds'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = mty.lrequire'pegl'

local M = {}

M.tokenizer = function(p)
  mty.pntf('?? tokenizing: '..p.line:sub(p.c))
  if p:isEof() then return end
  return (
    p.line:match('^[%[%]=`]', p.c)
    or p.line:match('^%S+', p.c)
  )
end

M.word = Pat{'[^%s%[%]=]+'}

M.inlineCode = {'`', Many{Not{'`'}}, '`', kind='inlineCode'}

M.attr  = {M.word, Maybe{'=', M.word}, kind='attr'}
M.ctrl = {kind='ctrl', '[', Many{M.attr}, ']'}

M.src = {Many{Or{M.inlineCode, M.ctrl, M.word}}, Eof}

M.defaultRoot = function()
  return pegl.RootSpec{tokenizer=M.tokenizer}
end

M.parse = function(dat, spec, root)
  root = root or M.defaultRoot()
  if not root.tokenizer then root.tokenizer = M.tokenizer end
  return pegl.parse(dat, spec, root)
end

return M

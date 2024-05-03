local DOC = [[
flux: simple change management (version control) software.
]]

METATY_DOC = true
local pkg = require'pkglib'
local shim     = require'shim'
local mty      =  require'metaty'
local ds       =  require'ds'
local df       =  require'ds.file'
local tso      =  require'tso'
local vcds     =  require'vcds'
local patience =  require'patience'
local civix    =  require'civix'

local pc = ds.path.concat

local M = {DOC=DOC}

-------------------------
-- Data Types
-- These are stored and indexed in the TSO file.

-- M.EntryMeta = mty.doc[[metadata for Entry]]
-- (mty.record2'flux.EntryMeta') {
--   'author[string]',
-- [[dateLog\
--   table of important dates in form
--     {'createdBranchName:2024-1-12', ..., 'finalBranchName:2024-1-24'}
--     Tools or users may choose to eliminate items in the middle.
-- ]],
--   'tags: list of string tags',
--   'signature[string]',
-- }
-- 
-- M.Entry = mty.doc[[
-- A single row in the flux database (indexed TSO document, SQLite database, etc)
-- ]](mty.record'flux.Entry')
--   :field('id', 'number'):fdoc'unique monotomically incrementing id'
--   :fieldMaybe('meta', M.EntryMeta)
--   :field'entry':fdoc'one of: Files, Post, Remove'
-- 
-- M.File = mty.doc[[
-- Part of Files. Encompases changes to one file.
-- Is a list of vcds.Change
-- ]](mty.record'flux.File')
--   :field('path', 'string')
--   :fieldMaybe('op', 'string'):fdoc[[
--   Special operation
--     'c'           create file
--     'd'           delete file
--     '=new/path'   move file
--   ]]
-- 
-- M.Branch = mty.doc[[
-- Create a branch point for Files.
-- 
-- This can appear multiple times in a flux stream. Each time it effectively
-- removes previous Files entries and starts at the new branch point.
-- 
-- This means a rebase does not delete data, only inserts a Branch
-- and the cherry-picked Files entries. Any PostFile items are kept
-- but effectively invalidated.
-- ]](mty.record'flux.Root')
--   :field('id',   'number'):fdoc'starting id of where this branched from'
--   :field('from', 'string'):fdoc'name of the branch this came from'
-- 
-- M.Files = mty.doc[[
-- Entry for changes to a list of flux.File
-- ]]
-- (mty.record'flux.Files')
--   :field('summary', 'string')
--   :fieldMaybe('description', 'string'):fdoc'detailed description'
--   :fieldMaybe('signature', 'string')
-- 
-- -- Post Ops
-- M.PostRoot = mty.doc'new thread with title'(mty.record'flux.PostRoot')
--   :field('title', 'string')
-- M.PostReply = mty.record'flux.PostReply'
--   :field('id', 'string'):fdoc'reply to post at branch:id'
-- M.PostEdit = mty.record'flux.PostEdit'
--   :field('id', 'string'):fdoc'edit post at branch:id'
-- M.PostFile = mty.record'flux.PostFile'
--   :field('id', 'string'):fdoc'comment on Files at branch:id'
--   :field('path', 'string')
--   :fieldMaybe('line', 'number')
--     :fdoc[[line number. negative is base, positive changed]]
-- 
-- M.Post = mty.doc[[
-- User post. Is list of vcds.Change
-- ]](mty.record'flux.Post')
--   :field'op':fdoc'oneof: Post(Root|Reply|Edit|File)'
--   :field('edit', 'boolean', false)
--     :fdoc'if false is new post, else is edit to existing'
--   :field('author', 'string')

-------------------------
-- Flux Operations

M.openSer = function(path)
  local lf = df.LinesFile{
    file = io.open(x:mainPath(), 'w'),
    cache = 5,
    len = true,
  }
  return tso.Ser{dat=lf}
end

M.Flux = mty.record'Flux'
  :field('path', 'string', './')

M.Flux.dir    = function(x)       return pc{x.path, '.flux'} end
M.Flux.brPath = function(x, name) return pc{x:dir(), name..'.br'} end

M.Flux.createBranch = function(x, name, base)
  local path = x:brPath(name)
  local ser = M.openSer(x:brPath(name))
  ser:attr('flux', {
    version = '0.0.1',
  })
  ser:attr('branch', name)
  ser:attr('base', base or ds.none)
end

M.Flux.init = function(x)
  if civix.exists(x:dir()) then
    return mty.pnt'flux: .flux/ directory already exists'
  end
  civix.mkDir(x:dir())
end

M.diff = function(path)

end

M.commitExe = function(args, isExe)
  mty.pnt'?? Running flux commit'
end

M.shim = shim {
  help = M.DOC,
  subs = {
    commit = shim {
      exe = M.commitExe,
      help = 'commit changes',
    },
  },
  exe = M.exe,
}

return M

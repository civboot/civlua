local P = {}
P.summary = "civ build system and developer software stack"
local lua = import'sys:lua.luk'

P.civ = lua {
  mod = 'civ',
  src = {
    'civ.lua',
    'core.lua',
    'Worker.lua',
  },
  dep = {
    'civ:lib/civix',
    'civ:lib/vt100',
    'civ:lib/pod',
    'civ:lib/luk',
    'civ:lib/lson',
    'civ:lib/lines',
    'civ:lib/civtest',
  },
  tag = { builder = 'bootstrap' },
  link = {['lua/civ.lua'] = 'bin/civ'},
}

P.test_civ = lua.test {
  src = 'test_civ.lua',
  dep = {
    'civ:cmd/civ',
  }
}

-- local FILE = 'https://github.com/civboot/civlua/blob/main/'
-- local FILE_LINE = FILE..'%s#L%s'
-- local RENDERED = 'https://html-preview.github.io/'
--                ..'?url=https://github.com/civboot/civlua/main/'
-- local EXT_PAT = '%.(%w+)$'
-- local USE_RENDERED = {html='html', cxt='html'}
-- 
-- html = {
--   pathUrl = function(p)
--     if USE_RENDERED[p:match(EXT_PAT)] then return p:gsub(EXT_PAT, USE_RENDERED) end
--     if p:match':(%d+)$' then
--       return FILE_LINE:format(p:match'^(.*):(%d+)$')
--     end
--     return FILE..p
--   end,
-- }
--

return P


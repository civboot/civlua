summary'civ build system and developer software stack'
import {
  lua   = 'sys:lua',
  ix    = 'civ:lib/civix',
  vt100 = 'civ:lib/vt100',
}

pkg {
  name    = 'civ',
  version = '0.1-0',
  url     = 'git+http://github.com/civboot/civlua',
  doc     = 'README.cxt',
  repo    = 'https://github.com/civboot/civlua',
  homepage = 'https://lua.civboot.org',
}

P.civ = lua {
  mod = 'civ',
  src = {
    'civ.lua',
    'core.lua',
  },
  dep = {
    ix.civix,
    vt100.vt100,
  },
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

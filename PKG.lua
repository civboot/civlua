name    = 'civ'
version = '0.1-0'
url     = 'git+http://github.com/civboot/civlua'
doc     = 'README.cxt'
repo    = 'https://github.com/civboot/civlua'
homepage = 'https://lua.civboot.org'
srcs = { 'civ.lua' }
pkgs = {
  -- lib/pkg: better lua package management

  -- Core
  'lib/shim',    -- cmdline args library
  'lib/metaty',  -- simple types based on metatables
  'lib/fmt',     -- formatting for types (and raw tables)
  'lib/civtest', -- simple unit testing
  'lib/ds',      -- data structures and algorithms
  'lib/lines',   -- work with files as a table of lines
  'lib/pod',     -- de/serialize plain-old-data
  'lib/lap',     -- lua asynchronous protocol
  'lib/fd',      -- asynchronous filedescriptors
  'lib/civix',   -- civlua unix interface
  'lib/lson',    -- JSON and binary-supporting LSON serde
  'lib/pegl',    -- PEG-like parsing library

  -- data storage / vcs
  'lib/luck',    -- user configuration
  'lib/smol',    -- binary diffs and compression
  'lib/civdb',   -- minimalist CRUD database
  'lib/vcds',

  -- Interacting with the user
  'ui/asciicolor', -- simple style and color to the user
  'ui/vt100',    -- VT100 terminal interface

  -- cmd
  'cmd/cxt',     -- simple text markup language
  'cmd/doc',     -- read and write inline documentation
  'cmd/ff',      -- fast-find and replace tool
  'cmd/pkgrock', -- interface with luarocks
  'cmd/pvc',     -- patch version control
  'cmd/ele',     -- Extendable Lua Editor (and shell)
}

local FILE = 'https://github.com/civboot/civlua/blob/main/'
local FILE_LINE = FILE..'%s#L%s'
local RENDERED = 'https://html-preview.github.io/'
               ..'?url=https://github.com/civboot/civlua/main/'
local EXT_PAT = '%.(%w+)$'
local USE_RENDERED = {html='html', cxt='html'}

html = {
  pathUrl = function(p)
    if USE_RENDERED[p:match(EXT_PAT)] then return p:gsub(EXT_PAT, USE_RENDERED) end
    if p:match':(%d+)$' then
      return FILE_LINE:format(p:match'^(.*):(%d+)$')
    end
    return FILE..p
  end,
}

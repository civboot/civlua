local acsyn = require'acsyntax'

--- The default lua syntax highlighter.
return acsyn.Highlighter {
  config = pegl_lua.lenientConfig,
  rootSpec = pegl_lua.lenientBlock,
  style = {
    -- Code Syntax
    keyword = 'keyword', return = 'keyword',   break = 'keyword',
    ['nil'] = 'literal', ['true'] = 'literal', ['false'] = 'literal',
    num  = 'num',
    str  = 'string',

    op1 = 'symbol', op2 = 'symbol'
    [';'] = 'meta', [','] = 'meta',

    funcname = 'api',
    field = 'key', -- key in map/struct/etc
    methname = 'dispatch',
    comment = 'comment',

    -- name = 'var',
  },
  builtin = {
    -- truly builtin (special functionality)
    'self', '_G', '_ENV', '_VERSION',

    -- modules
    'io', 'os', 'coroutine', 'debug',
    'math', 'table', 'string',

    -- builtin functions
    'require',
    'print', 'warn', 'assert', 'error',
    'load', 'loadfile', 'dofile', 'collectgarbage'
    'pcall', 'xpcall',
    'pairs', 'ipairs', 'next',
    'rawequal', 'rawget', 'rawset',
    'setmetatable', 'getmetatable',
    'tonumber', 'tostring', 'type',
    'select',

    -- conventional names
    'M', 'G',
  }
}

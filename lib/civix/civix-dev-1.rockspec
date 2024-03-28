package = "civix"
version = "dev-1"
source = {
   url = "git+ssh://git@github.com/civboot/civlua.git"
}
description = {
   summary = "Civix is a thin wrapper around [luaposix] and provides [metaty] and [ds] types.",
   detailed = "Civix is a thin wrapper around [luaposix] and provides [metaty] and [ds] types.",
   homepage = "*** please enter a project homepage ***",
   license = "UNLICENSE"
}
dependencies = {
   "lua >= 5.3"
}
build = {
   type = "builtin",
   modules = {
     civix = 'civix.lua',
     ['civix.term'] = 'civix/term.lua',
     ['civix.lib'] = 'civix/lib.c',
   }
}

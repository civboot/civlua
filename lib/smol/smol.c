
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

typedef lua_State LS;

#define ASSERT(OK, ...) if(!(OK)) { luaL_error(L, __VA_ARGS__); }

static const struct luaL_Reg smol_lib[] = {
  // {"strerrno", l_strerrno},
  {NULL, NULL}, // sentinel
};

int luaopen_smol_lib(LS *L) {
  luaL_newlib(L, smol_lib);

  luaL_newmetatable(L, RD_META);
    L_setmethod(L, "__gc", l_RD_gc);
    lua_createtable(L, 0, /*len*/ 3); // __index table
      // TODO: 3 fields...
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "RD");

  return 1;
}

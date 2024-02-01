#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

extern int l_mul(lua_State *L) {
  lua_Integer n1 = luaL_checkinteger(L, 1);
  lua_Integer n2 = luaL_checkinteger(L, 2);
  lua_pushinteger(L, n1 * n2);
  return 1;
}

// static const struct luaL_Reg civbase[] = {
//   // {"mul", l_mul},
//   {NULL, NULL} // sentinel
// };
// 
// int luaopen_civbase(lua_State *L) {
//   luaL_openlib(L, "civbase", civbase, 0);
//   return 1;
// }

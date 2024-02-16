#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

extern int l_hash3(lua_State *L) {
  lua_Integer k = luaL_checkinteger(L, 1);

  lua_pushinteger(L, n1 * n2);
  return 1;
}

static const struct luaL_Reg pear[] = {
  // {"mul", l_mul},
  {NULL, NULL} // sentinel
};

LUALIB_API luaopen_civbase(lua_State *L) {
#if LUA_VERSION_NUM >= 502 // LUA 5.2 or above
  lua_newtable(L);
  luaL_setfuncs(L, pear, 0);
#else
  luaL_register(L, "pear", xxtea);
#endif
  return 1;
}

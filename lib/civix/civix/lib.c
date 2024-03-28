#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>

int l_epoch(lua_State *L) {
  struct timespec spec = {};
  clock_gettime(CLOCK_REALTIME, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
}

static const struct luaL_Reg civix_lib[] = {
  {"epoch", l_epoch},
  {NULL, NULL} // sentinel
};

int luaopen_civix_lib(lua_State *L) {
  luaL_newlib(L, civix_lib);
  return 1;
}

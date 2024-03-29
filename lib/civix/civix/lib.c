#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>

int gettime(lua_State *L, clockid_t clk_id) {
  struct timespec spec = {};
  clock_gettime(CLOCK_REALTIME, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
} int l_epoch(lua_State *L) { return gettime(L, CLOCK_REALTIME); }
  int l_mono(lua_State *L) { return gettime(L, CLOCK_MONOTONIC); }

static const struct luaL_Reg civix_lib[] = {
  {"epoch", l_epoch},
  {"mono",  l_mono},
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(lua_State *L) {
  luaL_newlib(L, civix_lib);
  return 1;
}

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>   // Time
#include <string.h> // Dir
#include <dirent.h> // Dir
#include <errno.h>  // Dir

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// ---------------------
// -- Time
int gettime(lua_State *L, clockid_t clk_id) {
  struct timespec spec = {};
  clock_gettime(CLOCK_REALTIME, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
} int l_epoch(lua_State *L) { return gettime(L, CLOCK_REALTIME);  }
  int l_mono(lua_State *L)  { return gettime(L, CLOCK_MONOTONIC); }

// ---------------------
// -- Dir
const char* DIR_NAME = "civix.Dir";

typedef DIR** UdDir; // Userdata which handles GC
  static void UdDir_gc(UdDir dir) {
    if(*dir) { closedir(*dir); *dir = NULL; }
  }
  static int l_dir_gc(lua_State *L) {
    UdDir_gc((UdDir)lua_touserdata(L, 1)); return 0;
  }

static int dir_iter(lua_State *L) {
	UdDir dir = (UdDir) lua_touserdata(L, lua_upvalueindex(1));
  if(*dir == NULL) return 0; // already freed
  struct dirent* ent; if((ent = readdir(*dir)) != NULL) {
    lua_pushstring(L, ent->d_name);
    return 1;
  }
  UdDir_gc(dir); // free early
  return 0;
}

static int l_dir(lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  UdDir dir = (UdDir)lua_newuserdata(L, sizeof(UdDir)); // stack: dir
  luaL_getmetatable(L, DIR_NAME);                       // stack: dir, Dir
  lua_setmetatable(L, -2);                              // stack: dir
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, strerror(errno));
  lua_pushcclosure(L, dir_iter, 1); 										// stack: (empty)
  return 1;
}

// ---------------------
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"epoch", l_epoch}, {"mono",  l_mono}, // Time
  {"dir", l_dir},                        // Dir
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(lua_State *L) {
  // civix.Dir metatable
  luaL_newmetatable(L, DIR_NAME);    // stack: Dir
  lua_pushstring(L, "__gc");         // stack: Dir, "__gc"
  lua_pushcfunction(L, l_dir_gc);    // stack: Dir, "__gc", l_dir_gc
  lua_settable(L, -3);               // stack: Dir
  lua_settop(L, 0);                  // stack: (empty)

  luaL_newlib(L, civix_lib);         // stack: civix.lib (library)
  return 1;
}


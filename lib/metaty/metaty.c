#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <string.h>
#include <assert.h>

typedef lua_State LS;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// concat(sep, ...) --> string
// concatenate all values (calling tostring on them) separated by sep.
static inline int l_concat(LS* L) {
  size_t slen; uint8_t const* sep = luaL_checklstring(L, 1, &slen);
  int lasti = lua_gettop(L);
  if(lasti == 1) { lua_pushstring(L, ""); return 1; }
  size_t vlen;
  // First compute the size and allocate the exact space we need
  size_t size = slen * (lasti - 2);  // size of all separators
  for(int i=2; i <= lasti; i++) {
    ASSERT(L, lua_tolstring(L, i, &vlen), "arg[%I] is not a string or number", i)
    size += vlen;
  }
  luaL_Buffer lb;
  char* b = luaL_buffinitsize(L, &lb, size); ASSERT(L, b, "OOM");
  const char* v = lua_tolstring(L, 2, &vlen);
  memcpy(b, v, vlen); b += vlen;
  for(int i = 3; i <= lasti; i++) {
    memcpy(b, sep, slen); b += slen;
    v = lua_tolstring(L, i, &vlen);
    memcpy(b, v, vlen); b += vlen;
  }
  luaL_pushresultsize(&lb, size);
  return 1;
}

// (t, update) -> t
static int l_update(LS* L) {
  if(!lua_istable(L, 1)) luaL_error(L, "arg[1] must be table");
  if(!lua_istable(L, 2)) luaL_error(L, "arg[2] must be table");
  lua_settop(L, 3); lua_pushnil(L); // stack: t, upd, k, nil
  while(lua_next(L, 2)) { // iterate through update
    lua_copy(L, 4, 3); lua_settable(L, 1);
    lua_pushnil(L);    lua_copy(L, 3, 4);
  }
  lua_settop(L, 1);
  return 1;
}

// push v to the end of table, returning the index
// (t, v) --> index
static int l_push(LS* L) {
  if(!lua_istable(L, 1)) luaL_error(L, "arg[1] must be table");
  lua_len(L, 1); lua_Integer i = lua_tointeger(L, -1) + 1;
  lua_settop(L, 2); lua_seti(L, 1, i);
  lua_pushinteger(L, i); return 1;
}

static const struct luaL_Reg metaty_native[] = {
  {"concat", l_concat},
  {"update", l_update},
  {"push",   l_push},
  {NULL, NULL},
};

int luaopen_metaty_native(LS *L) { luaL_newlib(L, metaty_native); return 1; }


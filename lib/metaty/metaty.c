#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <assert.h>

typedef lua_State LS;

// concat(sep, ...) --> string
// concatenate all values (calling tostring on them) separated by sep.
static inline int l_concat(LS* L) {
  size_t slen; uint8_t const* sep = luaL_checklstring(L, 1, &slen);
  int lasti = lua_gettop(L);
  if(lasti == 1) { lua_pushstring(L, ""); return 1; }
  int size = slen * (lasti - 2);  // size of all separators
  for(int i=2; i <= lasti; i++) { // convert tostring and calc bufsize
    luaL_tolstring(L, i, NULL); size += lua_rawlen(L, -1);
  }
  luaL_Buffer lb; luaL_buffinitsize(L, &lb, size);
  size_t alen; uint8_t const* arg;
  arg = lua_tolstring(L, lasti+1, &alen); luaL_addlstring(&lb, arg, alen);
  for(int i = lasti+2; i <= lasti + (lasti - 1); i++) {
    luaL_addlstring(&lb, sep, slen);
    arg = lua_tolstring(L, i, &alen); luaL_addlstring(&lb, arg, alen);
  }
  luaL_pushresult(&lb);
  return 1;
}

// copy from index f to index t
// Note: t+1 must be available to hold key
static void copyt(LS* L, int f, int t) {
  lua_pushnil(L);
  while(lua_next(L, f)) {
    lua_copy(L, t+2, t+1); lua_rawset(L, t);
    lua_pushnil(L); lua_copy(L, t+1, t+2);
  }
}

// (t, update) -> t: perform a shallow copy of table (not it's metatype)
// If update is given then modify those keys
static inline int l_copy(LS* L) {
  lua_newtable(L); int t = lua_gettop(L);
  if(t > 3) luaL_error(L, "copy only accepts args: (t, update)");
  lua_pushnil(L);  // key space
  copyt(L, 1, t);  // t -> newt
  if(t == 3 && !lua_isnil(L, 2)) copyt(L, 2, t);  // update -> newt
  lua_pop(L, 1); // pop key space
  return 1;
}

static const struct luaL_Reg metaty_native[] = {
  {"concat", l_concat}, {"copy", l_copy},
  {NULL, NULL},
};

int luaopen_metaty_native(LS *L) { luaL_newlib(L, metaty_native); return 1; }


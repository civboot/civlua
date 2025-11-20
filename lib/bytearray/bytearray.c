#include "bytearray.h"

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

typedef lua_State LS;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

//***********
// C API

bytearray* bytearray_new(LS* L) {
  bytearray* b = (bytearray*) lua_newuserdata(L, sizeof(bytearray));
  b->dat = NULL; b->len = 0; b->sz = 0;
  luaL_setmetatable(L, LUA_BYTEARRAY);
  return b;
}
bytearray* bytearray_close(bytearray* b) {
  if(b && b->dat) {
    free(b->dat); b->dat = NULL;
    b->len = 0; b->sz = 0;
  }
}

bytearray* asbytearray(LS* L, int index) {
  bytearray* b = luaL_testudata(L, index, LUA_BYTEARRAY);
  if(!b) luaL_error(L, "arg %I not a bytearray", index);
  return b;
}

bool bytearray_grow(bytearray* b, size_t sz) {
  if(sz <= b->sz) return true;
  sz += sz % 16; // make divisible by 16
  if(sz < (b->sz * 2)) sz = b->sz * 2; // at least double size
  uint8_t* dat = realloc(b->dat, sz); if(dat == NULL) return false;
  b->dat = dat; b->sz = sz;
  return true;
}

bool bytearray_extend(bytearray* b, uint8_t* dat, size_t len) {
  if(!bytearray_grow(b, b->len + len)) return false;
  memcpy(b->dat + b->len, dat, len);
  b->len += len;
  return true;
}

//***********
// Lua API

static int l_extend(LS* L) { // --> bytearray
  int top = lua_gettop(L); uint8_t* s; size_t len;
  bytearray* b = asbytearray(L, 1);
  size_t extend_len = 0;
  // Grow the bytearray first
  for(int i = 2; i <= top; i++) {
    ASSERT(L, lua_tolstring(L, i, &len), "arg %I is not a string", i);
    extend_len += len;
  }
  ASSERT(L, bytearray_grow(b, b->len + extend_len), "OOM");
  // Then add data.
  for(int i = 2; i <= top; i++) {
    s = (uint8_t*)lua_tolstring(L, i, &len);
    ASSERT(L, bytearray_extend(b, s, len), "unreachable");
  }
  lua_settop(L, 1);
  return 1;
}

static int l_call(LS* L) {
  bytearray* b = bytearray_new(L);
  lua_replace(L, 1);
  l_extend(L);
  ASSERT(L, b, "failed to allocate new bytearray");
  return 1;
}

static int l_bytearray_close(LS* L) {
  bytearray_close(asbytearray(L, 1));
  return 0;
}

static int l_tostring(LS* L) {
  bytearray* b = asbytearray(L, 1);
  lua_pushlstring(L, b->dat, b->len);
  return 1;
}

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_bytearray(LS *L) {
  luaL_newmetatable(L, LUA_BYTEARRAY);
    // bytearray fields/metamethods
    L_setmethod(L, "__gc",       l_bytearray_close);
    L_setmethod(L, "__tostring", l_tostring);
    lua_pushstring(L, "bytearray"); lua_setfield(L, -2, "__name");

    lua_newtable(L); // bytearray metatable
      lua_pushstring(L, "bytearray type"); lua_setfield(L, -2, "__name");
      L_setmethod(L, "__call", l_call); // constructor
    lua_setmetatable(L, -2);

    lua_newtable(L); // bytearray methods
      L_setmethod(L, "extend",     l_extend);
      L_setmethod(L, "to",         l_tostring);
    lua_setfield(L, -2, "__index");
  return 1;
}


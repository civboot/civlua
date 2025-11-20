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

bytearray* bytearray_new(LS* L) {
  return (bytearray*) lua_newuserdata(L, sizeof(bytearray));
}

bytearray* asbytearray(LS* L, int index) {
  bytearray* a = luaL_testudata(L, index, LUA_BYTEARRAY);
  if(!a) luaL_error(L, "arg %I not a bytearray", index); return NULL;
  return a;
}

int l_call(LS* L) {
  bytearray* b = bytearray_new(L);
  printf("!! l_call %i\n", lua_gettop(L));
  return 1;
}

int l_bytearray_close(LS* L) {
  bytearray* b = asbytearray(L, 1);
  if(b && b->dat) {
    free(b->dat); b->dat = NULL;
    b->sz = 0;
  }
  return 0;
}

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_bytearray(LS *L) {
  luaL_newmetatable(L, LUA_BYTEARRAY);
    lua_pushstring(L, "bytearray"); lua_setfield(L, -2, "__name");
    L_setmethod(L, "__gc", l_bytearray_close);

    lua_newtable(L); // metatable of bytearray type.
      lua_pushstring(L, "bytearray type"); lua_setfield(L, -2, "__name");
      L_setmethod(L, "__call", l_call); // constructor
    lua_setmetatable(L, -2);

  return 1;
}


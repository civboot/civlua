#ifndef BYTEARRAY_H
#define BYTEARRAY_H
#include <lua.h>
#include <stdint.h>
#include <stddef.h>

#define LUA_BYTEARRAY  "bytearray"

typedef struct _bytearray {
  uint8_t* dat;
  size_t sz;
} bytearray;

// Allocate bytearray whos memory will be managed by Lua.
bytearray* bytearray_new(lua_State* L);

bytearray* asbytearray(lua_State* L, int index);


int l_bytearray(lua_State* L);


#endif // BYTEARRAY_H

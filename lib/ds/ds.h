#ifndef DS_H
#define DS_H
#include <lua.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define LUA_BYTEARRAY  "bytearray"

// Lua library API
int luaopen_ds_lib(lua_State* L);

//***********
// C API

typedef struct _bytearray {
  uint8_t* dat;
  size_t len; // length of current data in bytearray
  size_t sz;  // allocated size of dat
  size_t pos; // file-like operations.
} bytearray;

// Allocate bytearray whos memory will be managed by Lua.
bytearray* bytearray_new(lua_State* L);

bytearray* asbytearray(lua_State* L, int index);

// Grow the bytearray.
// Return true if successful or if sz < b->sz.
bool bytearray_grow(bytearray* b, size_t sz);

// Extend the data onto the end of the bytearray
bool bytearray_extend(bytearray* b, uint8_t* d, size_t sz);


#endif // DS_H

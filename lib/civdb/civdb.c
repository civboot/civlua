
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <assert.h>

typedef lua_State LS;

#define ASSERT(OK, ...) if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// #define DBG(...) printf("!D! " __VA_ARGS__)
#define DBG(...)

// decode value from bytes. v: current value, s: current shift
static inline int decv(uint8_t** b, uint8_t* be, uint64_t* v, int s) {
  while((*b < be) && (0x80 & **b)) {
    *v |= ((0x7F & **b) << s);
    s += 7; *b += 1;
  }
  if(*b >= be) return -1;
  *v |= (**b << s); *b += 1;
  return 0;
}

// encode value to bytes. v: current value
static inline int encv(uint8_t** b, uint8_t* be, uint64_t v) {
  while((*b < be) && (v > 0x7F)) {
    **b = 0x80 | v; v = v >> 7; *b += 1;
  }
  if(*b >= be) return -1;
  **b = v; *b += 1;
  return 0;
}

//************************
//* 3.a binary enc/dec types

#define  B_TABLE    0x00
#define  B_KEYVAL   0x20
#define  B_STRING   0x40
#define  B_FLOAT    0x80
#define  B_PINT     0xA0
#define  B_NINT     0xC0
#define  B_BOOL     0xE0

int enclv(uint8_t** b, uint8_t* e, uint8_t ty, uint64_t v) {
  if(v > 0xFF) {
    **b = ty | 0x10 | (0xFF & v); *b += 1;
    return encv(b,e, v>>4);
  }
  **b = ty | v; *b += 1;
  return 0;
}

int l_encodeSmall(LS* L);

int encodeString(LS* L, uint8_t type) {
  size_t len; uint8_t const* s = lua_tolstring(L, -1, &len);
  lua_pop(L, 1);
  luaL_Buffer lb; luaL_buffinit(L, &lb);
  uint8_t* bs = luaL_buffinitsize(L, &lb, 8 + len);
  uint8_t* b = bs; ASSERT(0 == enclv(&b, b+8, type, len), "OOB");
  printf("!! encoded pre len=%i\n", b-bs);
  luaL_addsize(&lb, b-bs);
  luaL_addlstring(&lb, s, len);
  luaL_pushresult(&lb); return 1;
}

int encodeTable(LS* L) {
  ASSERT(lua_checkstack(L, 20), "OOM");
  // get the tablei and cache the next value before buffinit
  int tablei = lua_gettop(L);
  lua_pushnil(L); lua_next(L, tablei);
  luaL_Buffer lb; luaL_buffinit(L, &lb);
  int ti; uint8_t *s, *s2; size_t len, len2;
  uint8_t *bs, *b; size_t blen;

  for(ti = 1;;ti++) {
    lua_geti(L, tablei, ti);
    if(lua_isnil(L, -1)) { lua_pop(L, 1); break; }
    ASSERT(1 == l_encodeSmall(L), "unreachable");
    luaL_addvalue(&lb);
  }

  // loop through next(), keeping stack balanced by using cached tablei
  while(true) {
    lua_pushvalue(L, tablei+1);
    if(!lua_next(L, tablei)) break;
    lua_copy(L, -2, tablei+1); // copy key for next loop
    if(lua_isinteger(L, -2) && (lua_tointeger(L, -2) <= ti)) {
      lua_pop(L, 2); continue;
    }

    ASSERT(1 == l_encodeSmall(L), "unreachable"); // value
    s2 = (uint8_t*) lua_tolstring(L, -1, &len2); lua_pop(L, 1);
    ASSERT(1 == l_encodeSmall(L), "unreachable"); // key
    s = (uint8_t*) lua_tolstring(L, -1, &len); lua_pop(L, 1);
    blen = len + len2;
    bs = luaL_prepbuffsize(&lb, 8 + len + len2);
    b = bs; ASSERT(0 == enclv(&b, b+8, B_KEYVAL, blen), "OOB");
    luaL_addsize(&lb, b - bs);
    luaL_addlstring(&lb, s,  len);
    luaL_addlstring(&lb, s2, len2);
  }

  luaL_pushresult(&lb);
  return encodeString(L, B_TABLE);
}

int encodeNumber(LS* L) {
  ASSERT(lua_isinteger(L, -1), "float not supported");
  lua_Integer i = lua_tointeger(L, -1); lua_pop(L, 1);
  bool positive = (i >= 0); if(!positive) i = -i;
  uint8_t buf[9]; uint8_t* b = buf;
  ASSERT(0 == enclv(&b, b+9, positive ? B_PINT : B_NINT, i), "OOB");
  lua_pushlstring(L, buf, b-buf); return 1;
}

int encodeBoolean(LS* L) {
  uint8_t b = B_BOOL | (lua_toboolean(L, -1) ? 1 : 0);
  lua_pop(L, 1); lua_pushlstring(L, &b, 1); return 1;
}

// v -> string: encode value as binary
int l_encodeSmall(LS* L) {
  switch(lua_type(L, -1)) {
    case LUA_TNUMBER:  return encodeNumber(L);
    case LUA_TBOOLEAN: return encodeBoolean(L);
    case LUA_TSTRING:  return encodeString(L, B_STRING);
    case LUA_TTABLE:   return encodeTable(L);
    default:
      luaL_error(L, "unsupported lua type: %s", lua_typename(L, -1));
  }
  return 1;
}

int decodeLuaB(LS* L, uint8_t** b, uint8_t* be);
int decodeTable(LS* L, uint8_t* b, uint8_t* be) {
  lua_createtable(L, 0, 0); int ti = 1; // ti: table index
  while(b < be) {
    switch(decodeLuaB(L, &b, be)) {
      case 1: lua_rawseti(L, -2, ti); ti += 1; break;
      case 2: lua_rawset(L, -3);               break;
      default: luaL_error(L, "unknown table item");
    }
  }
  return 1;
}

int decodeLuaB(LS* L, uint8_t** b, uint8_t* be) {
  if(*b >= be) {
    if(*b == be) { return 0; } else { luaL_error(L, "OOB"); }
  }
  uint8_t ch = **b; *b += 1;
  uint64_t len = 0x0F & ch;
  if(0x10 & ch) ASSERT(decv(b,be, &len,4) >= 0, "OOB");

  uint8_t *vb, *ve; // value buffer/end
  #define SET_VP() vb = *b; *b += len; ASSERT(*b <= be, "OOB")
  switch(0xE0 & ch) {
    case B_TABLE: SET_VP(); return decodeTable(L, vb, vb+len);
    case B_KEYVAL:
      SET_VP(); ve = vb+len;
      ASSERT(1 == decodeLuaB(L, &vb, ve), "kv key not 1");
      ASSERT(1 == decodeLuaB(L, &vb, ve), "kv val not 1");
      return 2;
    case B_STRING: SET_VP(); lua_pushlstring(L, vb, len); return 1;
    case B_FLOAT: luaL_error(L, "not implemented");
    case B_PINT: lua_pushinteger(L, len);  return 1;
    case B_NINT: lua_pushinteger(L, -len); return 1;
    case B_BOOL: lua_pushboolean(L, len);  return 1;
    default: luaL_error(L, "decodeLuaB: unreachable");
  }
}

// string -> val: decode encoded lua value.
int l_decodeSmall(LS* L) {
  size_t len; uint8_t* s = (uint8_t*)luaL_checklstring(L, -1, &len);
  return decodeLuaB(L, &s, s+len);
}

//************************
//* 3.a Lua Bindings

// int -> str: encode integer using encv
static int l_encv(LS* L) {
  uint8_t buf[8]; uint8_t* b = buf; encv(&b, buf+8, luaL_checkinteger(L, 1));
  lua_pushlstring(L, buf, b-buf);
  return 1;
}

// str, startindex=1 -> (int, elen): decode integer using decv
// returns: the integer and the number of bytes used to encode it.
static int l_decv(LS* L) {
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 1, &tlen);
  int startindex = luaL_optinteger(L, 2, 1) - 1;
  if(startindex < 0) startindex = 0;
  uint8_t* tp = txt + startindex;
  uint64_t v = 0; ASSERT(decv(&tp, txt+tlen, &v,0) >= 0, "OOB");
  lua_pushinteger(L, v);
  lua_pushinteger(L, tp - txt - startindex);
  return 2;
}

static const struct luaL_Reg civdb_sys[] = {
  {"encv", l_encv}, {"decv", l_decv},
  {"encodeSmall", l_encodeSmall}, {"decodeSmall", l_decodeSmall},
  {NULL, NULL}, // sentinel
};


#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_civdb_sys(LS *L) {
  luaL_newlib(L, civdb_sys);

  return 1;
}


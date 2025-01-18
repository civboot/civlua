
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
static inline int decv(uint8_t const** b, uint8_t const* be, uint64_t* v, int s) {
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

#define  B_TABLE    0x00 /* indexed vals and key/vals */
#define  B_MAP      0x20 /* key/vals */
#define  B_LIST     0x40 /* indexed vals */
#define  B_BYTES    0x60
#define  B_POSITIVE 0x80 /*positive int*/
#define  B_NEGATIVE 0xA0 /*negative int*/
#define  B_RESERVED 0xC0 /*unused*/
#define  B_OTHER    0xE0 /*none, false, true, floats/etc*/

#define B_OTHER_NONE  0x00
#define B_OTHER_FALSE 0x01
#define B_OTHER_TRUE  0x02

// encode lua type and count
int enclv(uint8_t** b, uint8_t* e, uint8_t ty, uint64_t v) {
  if(*b >= e) return -1;
  if(v > 0x0F) {
    **b = ty | 0x10 | (0x0F & v); *b += 1;
    return encv(b,e, v>>4);
  }
  **b = ty | v; *b += 1;
  return 0;
}

// decode lua type and count
int declv(uint8_t const** b,uint8_t const* e, uint64_t* v, uint8_t* ty) {
  if(*b >= e) return -1;
  uint8_t c = **b; *b += 1; *ty = 0xE0 & c; *v = 0x0F & c;
  if(0x10 & c) return decv(b,e, v,4);
  return 0;
}

void encode(LS* L);

void encodeString(LS* L, uint8_t type) {
  size_t len; uint8_t const* s = lua_tolstring(L, -1, &len);
  lua_pop(L, 1);
  luaL_Buffer lb; uint8_t* bs = luaL_buffinitsize(L, &lb, 8 + len);
  uint8_t* b = bs; ASSERT(0 == enclv(&b, b+8, type, len), "OOB");
  printf("!! encoded pre len=%i\n", b-bs);
  luaL_addsize(&lb, b-bs);
  luaL_addlstring(&lb, s, len);
  luaL_pushresult(&lb);
}

void encodeTable(LS* L) {
  // get the tablei and cache the next value before buffinit
  int tablei = lua_gettop(L);
  size_t llen = lua_rawlen(L, tablei), mlen = 0; // list/map lens
  lua_pushnil(L); while(lua_next(L, tablei)) {
    lua_pop(L, 1); // pop value
    if(!lua_isinteger(L, -1) || (lua_tointeger(L, -1) > llen)) mlen += 1;
  }
  ASSERT(lua_checkstack(L, 20 + llen + mlen), "not enough stack");
  lua_pushnil(L); // for map loop, needed BEFORE buffinit
  luaL_Buffer lb; luaL_buffinit(L, &lb); // stack must balance until EoF
  uint8_t* bs = luaL_prepbuffsize(&lb, 16); uint8_t* b = bs;
  if(mlen) {
    ASSERT(0 == enclv(&b,bs+16, llen ? B_TABLE : B_MAP, mlen), "OOB");
    if(llen) ASSERT(0 == encv(&b,bs+16,llen), "OOB");
  } else ASSERT(0 == enclv(&b,bs+16, B_LIST, llen), "OOB");
  luaL_addsize(&lb, b-bs);

  for(int i=1; i <= llen; i++) { // serialize list items
    lua_geti(L, tablei, i);
    encode(L);
    luaL_addvalue(&lb);
  }

  uint8_t *s; size_t len;
  while(true) { // serialize map items
    lua_pushvalue(L, tablei+1); if(!lua_next(L, tablei)) break;
    lua_copy(L, -2, tablei+1); // copy key for next loop
    if(lua_isinteger(L, -2) && (lua_tointeger(L, -2) <= llen)) {
      lua_pop(L, 2); continue;
    }

    encode(L);
    ASSERT(tablei+3 == lua_gettop(L), "tablei=%I i=%I", tablei, lua_gettop(L));
    s = (uint8_t*) lua_tolstring(L, -1, &len); lua_pop(L, 1);

    encode(L);
    ASSERT(tablei+2 == lua_gettop(L), "tablei=%I i=%I", tablei, lua_gettop(L));
    size_t len2; uint8_t const* s2 = lua_tolstring(L, -1, &len2);
    printf("!! encoded key: %.*s\n",   len2, s2);
    printf("!! encoded value: %.*s\n", len,  s);

    luaL_addvalue(&lb);           // key
    luaL_addlstring(&lb, s, len); // value
  }

  luaL_pushresult(&lb); // push encoded, end use of buffer
  lua_replace(L, tablei); lua_pop(L, 1); // replace table and pop nextv
}

void encodeNumber(LS* L) {
  ASSERT(lua_isinteger(L, -1), "float not supported");
  lua_Integer i = lua_tointeger(L, -1); lua_pop(L, 1);
  bool positive = (i >= 0); if(!positive) i = -i;
  uint8_t buf[9]; uint8_t* b = buf;
  ASSERT(0 == enclv(&b, b+9, positive ? B_POSITIVE : B_NEGATIVE, i), "OOB");
  lua_pushlstring(L, buf, b-buf);
}

void encodeBoolean(LS* L) {
  uint8_t b = B_OTHER | (lua_toboolean(L, -1) ? B_OTHER_TRUE : B_OTHER_FALSE);
  lua_pop(L, 1); lua_pushlstring(L, &b, 1);
}

// v -> string: encode value as binary
void encode(LS* L) {
  switch(lua_type(L, -1)) {
    case LUA_TNUMBER:  return encodeNumber(L);
    case LUA_TBOOLEAN: return encodeBoolean(L);
    case LUA_TSTRING:  return encodeString(L, B_BYTES);
    case LUA_TTABLE:   return encodeTable(L);
    default:
      luaL_error(L, "unsupported lua type: %s", lua_typename(L, -1));
  }
}

int l_encode(LS* L) {
  encode(L); return 1;
}

void decodeLuaB(LS* L, uint8_t const** b, uint8_t const* be);
void decodeTable(LS* L,
                 uint8_t const** b, uint8_t const* be,
                 uint8_t ty, uint64_t v) {
  uint64_t llen = 0, mlen = 0;
  switch (ty) {
    case B_TABLE:
      mlen = v;
      ASSERT(0 == decv(b,be, &llen,0), "OOB");
      break;
    case B_MAP:  mlen = v; break;
    case B_LIST: llen = v; break;
    default: luaL_error(L, "unknown table type");
  }

  lua_createtable(L, llen, mlen);
  for(uint64_t i = 1; i <= llen; i++) {
    decodeLuaB(L, b, be);
    lua_rawseti(L, -2, i);
  }
  for(uint64_t i = 1; i <= mlen; i++) {
    decodeLuaB(L, b, be);
    decodeLuaB(L, b, be);
    lua_rawset(L, -3);
  }
}

void decodeLuaB(LS* L, uint8_t const** b, uint8_t const* be) {
  if(*b >= be) luaL_error(L, "OOB");
  printf("!! decoding LuaB\n");
  uint64_t v; uint8_t ty; ASSERT(0 == declv(b,be, &v,&ty), "OOB");
  printf("!!   ty=0x%X v=%li\n", ty, v);
  switch(ty) {
    case B_TABLE:
    case B_MAP:
    case B_LIST: return decodeTable(L, b,be, ty,v);
    case B_BYTES:
      lua_pushlstring(L, *b, v);
      *b += v;
      return;
    case B_POSITIVE: lua_pushinteger(L, v);  return;
    case B_NEGATIVE: lua_pushinteger(L, -v); return;
    case B_OTHER: switch(v) {
      case B_OTHER_FALSE: lua_pushboolean(L, false); return;
      case B_OTHER_TRUE:  lua_pushboolean(L, true);  return;
      default: // fallthrough
    }
    default: luaL_error(L, "decodeLuaB: unreachable");
  }
}

// (string, index=1) -> (val, encodelen)
// decode encoded lua value starting at index. Return
// the decoded value and the length of the string used.
int l_decode(LS* L) {
  size_t len; uint8_t const* s = luaL_checklstring(L, 1, &len);
  lua_Integer i = luaL_optinteger(L, 2, 1);
  ASSERT((i >= 1) && (i <= len + 1), "invalid index");
  uint8_t const* se = s + len; s = s + i - 1;
  uint8_t const* b = s;
  if(b >= s + len) lua_pushnil(L);
  else             decodeLuaB(L, &b, se);
  lua_pushinteger(L, b - s);
  return 2;
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
  size_t tlen; uint8_t const* txt = luaL_checklstring(L, 1, &tlen);
  int startindex = luaL_optinteger(L, 2, 1) - 1;
  if(startindex < 0) startindex = 0;
  uint8_t const* tp = txt + startindex;
  uint64_t v = 0; ASSERT(decv(&tp, txt+tlen, &v,0) >= 0, "OOB");
  lua_pushinteger(L, v);
  lua_pushinteger(L, tp - txt - startindex);
  return 2;
}

static const struct luaL_Reg civdb_sys[] = {
  {"encv", l_encv}, {"decv", l_decv},
  {"encode", l_encode}, {"decode", l_decode},
  {NULL, NULL}, // sentinel
};


#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_civdb_sys(LS *L) {
  luaL_newlib(L, civdb_sys);

  return 1;
}


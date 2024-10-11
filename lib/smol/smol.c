
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

typedef lua_State LS;
typedef struct stat STAT;

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);
#define ASSERT(OK, ...) if(!(OK)) { luaL_error(L, __VA_ARGS__); }

const char* RD_META = "smol.RD";
#define L_checkRD(L) (RD*) luaL_checkudata(L, 1, RD_META)

typedef struct _RD {
  char* dec;               // old+new decoded (aka raw) bytes 'base'..'change'
  // dec indexes: base/change (end), len, size
  size_t dlen, dsz;
  int db, dc;
  int dh;                  // rolling hash start

  // encoded bytes
  size_t elen, esz;
  char* enc; int ei;
} RD;

static void RD_freeDec(RD* x) {
  if(x->dsz) { free(x->dec); x->dlen = 0; x->dec = NULL; x->dsz = 0; }
}
static void RD_freeEnc(RD* x) {
  if(x->esz) { free(x->enc); x->elen = 0; x->enc = NULL; x->esz = 0; }
}
static int l_RD_gc(LS *L) {
  RD* x = L_checkRD(L);
  RD_freeDec(x);
  RD_freeEnc(x);
  return 0;
}

// (dsz, esz) -> RD
static int l_RD_create(LS* L) {
  int dsz = luaL_checkinteger(L, 1);
  int esz = luaL_checkinteger(L, 2);
  RD* x = (RD*)lua_newuserdata(L, sizeof(RD));
  *x = (RD) {0};
  if(dsz > 0) {
    x->dec = malloc(dsz); ASSERT(x->dec, "OOM dsz");
    x->dsz = dsz;
  }
  if(esz > 0) {
    x->enc = malloc(esz); ASSERT(x->dec, "OOM esz");
    x->esz = esz;
  }
  return 1;
}

// (rd, string) -> !?
// write the string to dec, incrementing len
// Throw if too large
static int l_RD_write(LS *L) {
  RD* rd = L_checkRD(L);
  size_t len; const char* s = luaL_checklstring(L, 2, &len);
  ASSERT(rd->dlen + len <= rd->dsz, "dec buffer overflow");
  memmove(rd->dec + rd->dlen, s, len);
  rd->dlen += len;
  return 0;
}
// (rd, baselen): set baselen (and dc)
// This is used after calling [$write] with the base+change data.
static int l_RD_baselen(LS *L) {
  RD* x = (RD*)L_checkRD(L);
  x->db = luaL_checkinteger(L, 2);
  x->dc = x->db;
}

// (rd, change?) -> string?
// * if string: set dec to change
// * else:      return [$change] as lua string
// WARNING: this class must not outlive any string set to it!
//
// Note: This is only useful if base is empty. If you want to set base and
//       change do RD_write and then use [$baseLen(len)]
static int l_RD_change(LS *L) {
  RD* x = (RD*)L_checkRD(L);
  if(lua_isnoneornil(L, 2)) lua_pushlstring(L, x->dec, x->dlen - x->dc);
  else {
    RD_freeDec(x);
    x->dec = (char*) luaL_checklstring(L, 2, &x->dlen);
  }
}

// (rd, encoded?) -> string? [+
// * if encoded: set enc to lua string.
// * else:       return [$enc] as lua string
// ]
// ["WARNING: this class must not outlive any string set to it!]
static int l_RD_enc(LS *L) {
  RD* x = (RD*)L_checkRD(L);
  if(lua_isnoneornil(L, 2)) lua_pushlstring(L, x->enc, x->elen);
  else {
    RD_freeEnc(x);
    x->enc = (char*) luaL_checklstring(L, 2, &x->elen);
  }
}

static int l_RD_decompress(LS* L) {
  RD* xp = (RD*)L_checkRD(L);
  RD x = *xp;

  ASSERT(x->dsz > 0, "decoding buffer not set");
  for(ssize_t i = 0; 

  *xp = x;
}

static const struct luaL_Reg smol_lib[] = {
  // {"strerrno", l_strerrno},
  {NULL, NULL}, // sentinel
};

int luaopen_smol_lib(LS *L) {
  luaL_newlib(L, smol_lib);

  luaL_newmetatable(L, RD_META);
    L_setmethod(L, "__gc", l_RD_gc);
    lua_createtable(L, 0, /*len*/ 3); // __index table
      // TODO: 3 fields...
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "RD");

  return 1;
}

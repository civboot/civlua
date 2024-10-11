
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

#define ADD  0x00
#define RUN  0x40
#define CPY  0x80


// https://en.wikipedia.org/wiki/Adler-32
#define MOD_ADLER 65521

//************************
//* Encode / Decode value

// decode value using initial value v from
// initial v(alue), b(uffer), s(hift), i(ndex), len
static inline int decv(int v, char* b, size_t len, int s, size_t* i) {
  while(0x80 & b[*i]) {
    v = ((0x7F & b[*i]) << s) | v;
    s += 7; *i += 1; if(*i > len) return -1;
  }
  v = (b[*i] << s) | v;
  *i += 1;
  printf("!! dec v=0x%x i=%i\n", v, *i);
  return v;
}
static inline int encv(int v, char* b, size_t len, size_t* i) {
  printf("!! enc v=0x%x\n", v);
  while(v > 0x7F) {
    b[*i] = 0x80 | v; v = v >> 7; *i += 1;
  }
  b[*i] = v; *i += 1;
  printf("!!   i=%i\n", *i);
  return 0;
}

#ifdef TEST
static void test_encode_v() {
  printf("test_decv\n");
  size_t i = 0;
  char b[12] = "\x85\x0F\x33";
  int v = decv(0, b,3, 0, &i);
  assert(i == 2);
  assert(v == ((0x0F << 7) | (0x5)));

 #define T_ROUND(V, IEXPECT) \
  i = 0; assert(0   == encv(V, b,12,    &i)); assert(i==IEXPECT); \
  i = 0; assert((V) == decv(0, b,12, 0, &i)); assert(i==IEXPECT);
  T_ROUND(0x00,  1);
  T_ROUND(0x01,  1); T_ROUND(0x37,  1); T_ROUND(0x07F,  1);
  T_ROUND(0x080, 2); T_ROUND(0x100, 2); T_ROUND(0x3FFF, 2);
  T_ROUND(0x4000, 3);
  T_ROUND(0x7FFFFFFF, 5);
#undef T_ROUND
}
#endif

//************************
//* Encode / Decode Commands

// decode the command and length. Return -1 on error.
static inline int decCmd(char* buf, size_t blen, size_t* i, int* len) {
  if(*i >= blen) return -1;
  int b = buf[*i]; *i += 1;
  *len = 0x1F & b; int cmd = 0xC0 & b;
  if(0x20 & b) *len = decv(*len, buf,blen, 5, i);
  printf("!! decCmd 0x%X b=0x%x len=0x%x i=%i\n", cmd, b, *len, *i);
  if(*len < 0) return -1;
  return cmd;
}

static inline int encCmd(char* buf, size_t blen, size_t* i, int cmd, int clen) {
  if(*i >= blen) return -1;
  printf("!! encCmd 0x%x len=0x%x i=%i\n", cmd, clen, *i);
  if (clen > 0x1F) {
    buf[*i] = cmd | 0x20 | (0x1F & clen); *i += 1;
    return encv(clen >> 5, buf,blen, i);
  } else {
    buf[*i] = cmd | clen; *i += 1;
  }
  return 0;
}

static inline int encRUN(char* buf, size_t len, size_t* i, int r, unsigned char b) {
  if(encCmd(buf,len,i, RUN,r)) return -1;
  if(*i >= len)                return -1;
  buf[*i] = b; *i += 1;
  printf("!! encRUN r=0x%x i=%i\n", r, *i);
  return 0;
}

static inline int encADD(char* buf, size_t blen, size_t* i, int a, char* str) {
  printf("!! encADD i=%i a=0x%x\n", *i, a);
  if(encCmd(buf,blen,i, ADD,a)) return -1;
  if(*i + a >= blen)            return -1;
  memcpy(&buf[*i], str, a);
  *i += a;
  printf("!!   add done i=%i\n", *i);
  return 0;
}

static inline int encCPY(char* buf, size_t blen, size_t* i, int cpy, int raddr) {
  printf("!! encCPY i=%i cpy=0x%x raddr=0x%x\n", *i, cpy, raddr);
  if(encCmd(buf,blen,i, CPY,cpy)) return -1;
  return encv(raddr, buf,blen,i);
}

#ifdef TEST
static void test_encode_cmds() {
  printf("test_encode_cmds\n");
  size_t i = 0; int len = 0;
  char b[32] = "\x43z";
  assert(RUN == decCmd(b,32,&i, &len)); assert(3 == len); assert(1 == i);

#define T_ROUND(CMD, LEN, EI, DI, ...) \
  i=0; assert(0 == enc##CMD(b,32,&i, LEN, __VA_ARGS__)); assert((EI)==i); \
  i=0; len=0; assert(CMD == decCmd(b,32,&i, &len)); assert((DI)==i); \
    assert(LEN == len);

  T_ROUND(RUN, 3,    2, 1, 'z'); assert(b[i] == 'z');
  T_ROUND(RUN, 0x50, 3, 2, 'y'); assert(b[i] == 'y');
  T_ROUND(ADD, 4,    5, 1, "test"); assert(0 == memcmp(b+i, "test", 4));
  T_ROUND(CPY, 7,    2, 1, 5); assert(5 == decv(0, b,32, 0, &i));
  T_ROUND(CPY, 7,    4, 1, 0x4000); assert(0x4000 == decv(0, b,32, 0, &i));
#undef T_ROUND
}
#endif


static const struct luaL_Reg smol_lib[] = {
  // {"strerrno", l_strerrno},
  {NULL, NULL}, // sentinel
};

// (base, encoded) -> change
static int l_decode(LS* L) {
  size_t blen; const char* base = luaL_checklstring(L, 1, &blen);
  size_t elen; const char* enc  = luaL_checklstring(L, 2, &elen);

  return 1;
}

#ifdef TEST
int main() {
  printf("Running tests\n");
  test_encode_v();
  test_encode_cmds();
  return 0;
}
#endif

int luaopen_smol_lib(LS *L) {
  luaL_newlib(L, smol_lib);

  return 1;
}


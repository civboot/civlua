
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


//************************
//* Encode / Decode value

// decode value using initial value v from
// initial v(alue), b(uffer), s(hift), i(ndex), len
static inline int decv(uint8_t* b, size_t len, size_t* i, int v, int s) {
  while(0x80 & b[*i]) {
    v = ((0x7F & b[*i]) << s) | v;
    s += 7; *i += 1; if(*i > len) return -1;
  }
  v = (b[*i] << s) | v;
  *i += 1;
  printf("!! dec v=0x%x i=%i\n", v, *i);
  return v;
}
static inline int encv(int v, uint8_t* b, size_t len, size_t* i) {
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
  printf("# test_decv (c)\n");
  size_t i = 0;
  uint8_t b[12] = "\x85\x0F\x33";
  int v = decv(b,3,&i, 0, 0);
  assert(i == 2);
  assert(v == ((0x0F << 7) | (0x5)));

 #define T_ROUND(V, IEXPECT) \
  i = 0; assert(0   == encv(V, b,12,    &i)); assert(i==IEXPECT); \
  i = 0; assert((V) == decv(b,12,&i, 0, 0)); assert(i==IEXPECT);
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
static inline int decCmd(uint8_t* buf, size_t blen, size_t* i, int* len) {
  if(*i >= blen) return -1;
  int b = buf[*i]; *i += 1;
  *len = 0x1F & b; int cmd = 0xC0 & b;
  if(0x20 & b) *len = decv(buf,blen,i, *len, 5);
  printf("!! decCmd 0x%X b=0x%x len=0x%x i=%i\n", cmd, b, *len, *i);
  if(*len < 0) return -1;
  return cmd;
}

static inline int encCmd(uint8_t* buf, size_t blen, size_t* i, int cmd, int clen) {
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

static inline int encRUN(uint8_t* buf, size_t len, size_t* i, int r, uint8_t b) {
  if(encCmd(buf,len,i, RUN,r)) return -1;
  if(*i >= len)                return -1;
  buf[*i] = b; *i += 1;
  printf("!! encRUN r=0x%x i=%i\n", r, *i);
  return 0;
}

static inline int encADD(uint8_t* buf, size_t blen, size_t* i, int a, uint8_t* str) {
  printf("!! encADD i=%i a=0x%x\n", *i, a);
  if(encCmd(buf,blen,i, ADD,a)) return -1;
  if(*i + a >= blen)            return -1;
  memcpy(&buf[*i], str, a);
  *i += a;
  printf("!!   add done i=%i\n", *i);
  return 0;
}

static inline int encCPY(uint8_t* buf, size_t blen, size_t* i, int cpy, int raddr) {
  printf("!! encCPY i=%i cpy=0x%x raddr=0x%x\n", *i, cpy, raddr);
  if(encCmd(buf,blen,i, CPY,cpy)) return -1;
  return encv(raddr, buf,blen,i);
}

#ifdef TEST
static void test_encode_cmds() {
  printf("# test_encode_cmds (c)\n");
  size_t i = 0; int len = 0;
  uint8_t b[32] = "\x43z";
  assert(RUN == decCmd(b,32,&i, &len)); assert(3 == len); assert(1 == i);

#define T_ROUND(CMD, LEN, EI, DI, ...) \
  i=0; assert(0 == enc##CMD(b,32,&i, LEN, __VA_ARGS__)); assert((EI)==i); \
  i=0; len=0; assert(CMD == decCmd(b,32,&i, &len)); assert((DI)==i); \
    assert(LEN == len);

  T_ROUND(RUN, 3,    2, 1, 'z'); assert(b[i] == 'z');
  T_ROUND(RUN, 0x50, 3, 2, 'y'); assert(b[i] == 'y');
  T_ROUND(ADD, 4,    5, 1, "test"); assert(0 == memcmp(b+i, "test", 4));
  T_ROUND(CPY, 7,    2, 1, 5); assert(5 == decv(b,32,&i, 0, 0));
  T_ROUND(CPY, 7,    4, 1, 0x4000); assert(0x4000 == decv(b,32,&i, 0, 0));
#undef T_ROUND
}
#endif

//************************
//* Addler32 Fingerprint Table

// addler32 struct
// https://en.wikipedia.org/wiki/Adler-32
#define MOD_ADLER 65521
typedef struct _A32 {
  uint8_t  *p, *end;
  uint32_t  a,  b;
} A32;
// start the A32 algorithm. This enables calculating multiple length
// fingerprints in one pass.
static inline void A32_start(A32* a, uint8_t* p, uint8_t* end) {
  a->p = p; a->end = end; a->a = 1; a->b = 0;
  printf("!! A32 start done\n");
}

// perform the loops and return the fingerprint. Updates p, a and b
static inline int A32_fp(A32* a, int loops) {
  for(; loops > 0; loops--) {
    printf("!! A32_fp loop a=%x b=%x p=%p end=%p\n", a->a, a->b, a->p, a->end);
    if(a->p >= a->end) break;
    a->a = (a->a + *a->p) % MOD_ADLER;
    a->b = (a->a +  a->b) % MOD_ADLER;
    a->p += 1;
  }
  return (a->b << 16) | a->a;
}

// fingerprint struct
typedef struct _FP {
  uint32_t* t;
  size_t    len;
} FP;

#define FP_NEW(NAME, LEN) \
  FP NAME = (FP) { \
    .len = LEN, .t = malloc((LEN) * sizeof(uint32_t)) \
  }; ASSERT((NAME).t, "OOM");

static inline void FP_init(FP* f) {
  for (size_t i=0; i < f->len; i++) f->t[i] = UINT32_MAX;
}

#define FP_FREE(NAME) free((NAME).t)
// calculate the fingerprint and set to i.
// Return the value that was previously there.
static inline uint32_t FP_set(FP* f, A32* a, uint32_t i) {
  printf("!! FP_set i=%i\n", i);
  uint32_t fp = A32_fp(a, 3);
  printf("!!   FP_set fp=%u (0x%x)\n", fp);
  uint32_t o = f->t[fp % f->len];
  printf("!!   FP_set o=%u (0x%x)\n", o, o);
               f->t[fp % f->len] = i;
  return o;
}

#ifdef TEST
void test_fp() {
  printf("# test_fp (c)\n");
  uint8_t* d = "0123456701234567";

  A32 a;

  #define T_LEN 7
  uint32_t t[T_LEN];
  FP f = {.t = t, .len = T_LEN};
  FP_init(&f);
  assert(UINT32_MAX == f.t[0]);
  assert(UINT32_MAX == f.t[T_LEN-1]);

  // insert and get the result (r) of one loop at I
  uint32_t r;
  #define testI(I, EXPECT) \
    printf("- fp.testI %u 0x%x\n", I, EXPECT); \
    A32_start(&a, d+(I), d+16); \
    r = FP_set(&f, &a, I); \
    printf("!! got r=%u (0x%x)\n", r, r); \
    assert(EXPECT == r);

  testI(0, UINT32_MAX); // index not found
  testI(0, 0);          // index found

  testI(1, UINT32_MAX);
  testI(1, 1); // 1 was inserted
  testI(0, 0); // 0 still there

  testI(8, 0); testI(8, 8); // strs at  d[0] and d[8] are same
  testI(9, 1); testI(9, 9); // same for d[1] and d[9]
  #undef testI
}
#endif

#ifdef TEST
int main() {
  printf("# TEST smol.c\n");
  test_encode_v();
  test_encode_cmds();
  test_fp();
  return 0;
}
#endif

//************************
//* Patch (decode) RDelta

// apply an rdelta
// (rdelta, base?) -> change
static int l_rpatch(LS* L) {
  size_t elen; uint8_t* enc  = (uint8_t*)luaL_checklstring(L, 1, &elen);
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 2, "", &blen);
  printf("!! rpatch elen=%i\n", elen);
  printf("!!        blen=%i base=%s\n", blen, base);
  size_t ei = 0; // enc index
  ASSERT(elen >= 1, "#rdelta == 0");
  // decode the length of the final output
  int clen = decv(enc,elen,&ei, 0, 0); ASSERT(clen >= 0, "clen");
  if(clen == 0) { lua_pushstring(L, ""); return 1; }
  clen = blen + clen;
  uint8_t* ch = malloc(clen); ASSERT(ch, "OOM");
  memcpy(ch, base, blen); size_t ci = blen;
  uint8_t* error = "OOB error";
  while(ei < elen) {
    // x == command
    int xlen; int x = decCmd(enc,elen,&ei, &xlen);
    switch (x) {
      case ADD:
        if((ei + xlen > elen) || (ci + xlen > clen)) goto error;
        memcpy(&ch[ci], &enc[ei], xlen); ei += xlen;
        break;
      case RUN:
        if((ei >= elen) || (ci + xlen > clen)) goto error;
        memset(&ch[ci], enc[ei], xlen);  ei += 1;
        break;
      case CPY:
        int raddr = decv(enc,elen,&ei, 0,0); if(raddr < 0) goto error;
        raddr = ci - raddr - xlen;
        if(raddr < 0)         { error = "negative CPY"; goto error; }
        if(raddr + xlen > ci) { error = "forward CPY";  goto error; }
        memcpy(&ch[ci], &ch[raddr], xlen);
        break;
      case -1: goto error;
      default: error = "unreachable"; goto error;
    }
    ci += xlen;
  }
  if(ci != clen) { error = "incorrect change length"; goto error; }
  lua_pushlstring(L, &ch[blen], clen - blen);
  free(ch);
  return 1;
error:
  free(ch);
  luaL_error(L, error); return 0;
}

//************************
//* Create (encode) rdelta



// create an rdelta
// (change, base?) -> delta
static int l_rdelta(LS* L) {
  char* err = NULL;
  size_t clen; uint8_t* change = (uint8_t*)luaL_checklstring(L, 1, &clen);
  if(clen == 0) { lua_pushlstring(L, "\0", 1); return 1; }
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 2, "", &blen);
  printf("!! rdelta clen=%i change=%s\n", clen, change);
  printf("!!        blen=%i base=%s\n", blen, base);

  size_t dlen = clen + blen;
  uint8_t* dec = malloc(dlen); ASSERT(dec, "OOM");

  // we fail if the encoded length == change length
  size_t elen = dlen * 2;
  uint8_t* enc = malloc(elen); ASSERT(enc, "OOM");

  // run character and length
  uint8_t rc; size_t rl;

  // fingerprint windows
  memcpy(dec, base, blen); memcpy(&dec[blen], change, clen);
#define W3_LEN 65497
  FP w3 = (FP) {
    .len = W3_LEN, .t = malloc((W3_LEN) * sizeof(uint32_t)),
  };
  ASSERT(w3.t, "OOM");
  memset(w3.t, 0xFF, w3.len);
  size_t wi = 0; // window index: what has been included in window
  int w3i;       // found index (maybe)
  uint32_t fp, a, b; // addler32 variables

  // https://en.wikipedia.org/wiki/Adler-32
  #define MOD_ADLER 65521
  #define ADDLER_INIT() a=1; b=0
  #define ADDLER32_1x(I) /* single loop of addler32 */ \
    a = (a + dec[I]) % MOD_ADLER; \
    b = (a + b)      % MOD_ADLER;
  #define ADDLER32_3x(I) /* 3x loop and set fp */ \
    ADDLER32_1x(I); ADDLER32_1x(I+1); ADDLER32_1x(I+2); \
    fp = (b << 16) | a

  int ws, we, i;    // window start/end indexes (definitely)
  // WIN_RANGE: macro to find the window range [ws:we)
  // algorithm: walk we from start until non-match,
  //       then walk ws from start-1 till no match.
  #define WIN_RANGE(W, SZ) { \
    we = W; i = 0;       \
    /* find end */       \
    while(dec[we+i] == dec[dc+i]) i++; \
    if(i >= SZ) {        \
      we += i - 1; /*found start+end*/ \
      ws = W; i = -1;    \
      /* try to find earlier start */   \
      while(dec[we+i] == dec[dc+i]) i--; \
      ws += i + 1;       \
    } else we = -1;      \
  }

  // encode final change len
  size_t ei = 0;
  if(encv(clen, enc,elen,&ei)) goto error; // -> nil

  // dc=start of change window we are looking at compressing
  size_t dc = blen; // TODO: compute initial windows

  // ai=add index in dec. ADD is the "fallback", we build up the bytes we want
  // to add and do it in one go immediately before other ops.
  size_t ai = dc;
  #define ENC_ADD() if(ai < dc) { \
    if(encADD(enc,elen,&ei, dc-ai, &dec[ai])) \
      goto error; /* -> nil */ \
  }

  while(dc < dlen) {
    printf("!! dc=%i\n", dc);
    for(; wi < dc; wi++) { // compute fingerprints we've missed
      ADDLER_INIT();
      ADDLER32_3x(wi);
      printf("!!   wi=0x%x fp=0x%x", wi, fp);
      w3.t[fp % w3.len] = wi;
    }

    // get w3i/w6i and clobber index (for future lookup)
    ADDLER_INIT();
    ADDLER32_3x(dc);
    w3i = w3.t[fp % w3.len]; w3.t[fp % w3.len] = dc;
    printf("!!   fp=0x%x (%i) got w3i=0x%x (and set 0x%x)", fp, w3i, dc);
    wi = dc + 1;

    ws = -1; we = -1;
    if(w3i < dc - 3) {
      we = w3i; i = 0;
      /* find end */
      while((dc+i < dlen) && (we+i < dc) && (dec[we+i] == dec[dc+i]))
        { i++; }
      if(i >= 3) {
        we += i - 1; /*found start+end*/
        ws = w3i; i = -1;    \
        /* try to find earlier start */
        while((we+i > 0) && (dc+i > 0) && (dec[we+i] == dec[dc+i]))
          { i--; }
        ws += i + 1;
      } else we = -1;
    }

    // compute run length
    rc = dec[dc]; rl = dc + 1; while(rc == dec[rl]) { rl++; }
    rl = rl - dc;
    #define ENC_RUN() do { \
      ENC_ADD();        \
      encRUN(enc,elen,&ei, rl, rc); \
      dc += rl; ai = dc;            \
    } while(0)

    printf("!!  0x%x rl=%i ws=%i we=%i\n", rc, rl, ws, we);
    if(we < 0) {
      if (rl > 3) ENC_RUN();
      else dc += 1;
    } else {
      ws = we - ws;       // copy length
      we = dc - we - 1; // relative-address of copy
      #define ENC_CPY() do { \
        ENC_ADD(); encCPY(enc,elen,&ei, ws, we); \
        dc += ws; ai = dc; \
      } while(0)

      // a == addr-length cost (+1 code byte) of copy
      // Note: we don't count the cost of LEN since if we need any length
      //       bytes the compression ratio is already phenominal.
           if(we < 127)     a = 2;
      else if(we < 16384)   a = 3;
      else if(we < 2097152) a = 4;
      else                  a = 5;

      // compression ratio
      #define CR1   16
      #define CR_80 13  /* 13/16 = 0.81 ~= 80% */
      #define CR(COST, LEN) (COST * 16) / (LEN)

      b = CR(a, ws); // copy compression ratio
      if((b < CR_80) && (b < CR(2, rl))) ENC_CPY();
      if(false);
      else if (rl > 3)                   ENC_RUN();
    }
  }
  ENC_ADD();
  lua_pushlstring(L, enc, ei);
  free(dec); free(enc);
  FP_FREE(w3);
  return 1;
error:
  free(dec); free(enc);
  FP_FREE(w3);
  ASSERT(!err, err);
  return 0;
}

static const struct luaL_Reg smol_sys[] = {
  {"rpatch", l_rpatch}, {"rdelta", l_rdelta},
  {NULL, NULL}, // sentinel
};

int luaopen_smol_sys(LS *L) {
  luaL_newlib(L, smol_sys);

  return 1;
}


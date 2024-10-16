
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

// gain from using RUN(0)/CPY(raddr)
// the cost of any command is the single byte to encode and the
// byte to encode the next run, as well as raddr for copy.
// We do NOT count the copy length since if it matters (aka it's >32)
// then we are going to compress anyway.
static inline int gain(int len, int raddr) {
  if(raddr <= 0x80     /*2^7 */) return len - 3;
  if(raddr <= 0x4000   /*2^14*/) return len - 4;
  if(raddr <= 0x200000 /*2^21*/) return len - 5;
}

//************************
//* Encode / Decode value

static inline int decv(uint8_t** b, uint8_t* be, int v, int s) {
  while((*b < be) && (0x80 & **b)) {
    v = ((0x7F & **b) << s) | v;
    s += 7; *b += 1;
  }
  if(*b >= be) return -1;
  v = (**b << s) | v; *b += 1;
  return v;
}

static inline int encv(uint8_t** b, uint8_t* be, int v) {
  printf("!! enc v=0x%x\n", v);
  while((*b < be) && (v > 0x7F)) {
    **b = 0x80 | v; v = v >> 7; *b += 1;
  }
  if(*b >= be) return -1;
  **b = v; *b += 1;
  return 0;
}

#ifdef TEST
static void test_encode_v() {
  printf("# test_decv (c)\n");
  size_t i = 0;
  uint8_t b[12] = "\x85\x0F\x33";
  uint8_t *bp = b, *be = b + 12;
  int v = decv(&bp,be, 0,0);
  printf("!! decv v=0x%x bp-b=%i\n", v, bp-b);
  assert((bp - b) == 2);
  assert(v == ((0x0F << 7) | (0x5)));

 #define T_ROUND(V, IEXPECT) \
  bp = b; assert(0   == encv(&bp, be, V));  assert(IEXPECT == bp-b); \
  bp = b; assert((V) == decv(&bp,be, 0,0)); assert(bp-b==IEXPECT);
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

static inline int deccmd(uint8_t** b, uint8_t* be, int* len) {
  if(*b >= be) return -1;
  uint8_t ch = **b; *b += 1;
  *len = 0x1F & ch; int cmd = 0xC0 & ch;
  if(0x20 & ch) *len = decv(b,be, *len,5);
  printf("!! decmd 0x%X ch=0x%x len=0x%x\n", cmd, ch, *len);
  if(*len < 0) return -1;
  return cmd;
}
static inline int enccmd(uint8_t** b, uint8_t* be, int cmd, int clen) {
  if(*b >= be) return -1;
  printf("!! encCmd 0x%x len=0x%x\n", cmd, clen);
  if (clen > 0x1F) {
    **b = cmd | 0x20 | (0x1F & clen); *b += 1;
    return encv(b,be, clen >> 5);
  }
  **b = cmd | clen; *b += 1;
  return 0;
}

static inline int encRUN(uint8_t** b,uint8_t* be, int r, uint8_t ch) {
  if(enccmd(b,be, RUN,r)) return -1;
  if(*b >= be)           return -1;
  **b = ch; *b += 1;
  printf("!! encRUN r=0x%x\n", r);
  return 0;
}

static inline int encADD(uint8_t** b,uint8_t* be, int addlen, uint8_t* str) {
  printf("!! encADD addlen=0x%x\n", addlen);
  if(enccmd(b,be, ADD,addlen)) return -1;
  if(*b + addlen >= be)        return -1;
  memcpy(*b, str, addlen); *b += addlen;
  return 0;
}

static inline int encCPY(uint8_t** b,uint8_t* be, int cpylen, int raddr) {
  printf("!! encCPY cpylen=0x%x raddr=0x%x\n", cpylen, raddr);
  if(enccmd(b,be, CPY,cpylen)) return -1;
  return encv(b,be, raddr);
}

#ifdef TEST
static void test_encode_cmds() {
  printf("# test_encode_cmds (c)\n");
  int len;
  uint8_t b[32] = "\x43z";
  uint8_t *bp=b, *be=b+32;

  assert(RUN == deccmd(&bp,be, &len));
  assert(3 == len); assert(1 == bp-b);

#define T_ROUND(CMD, LEN, EI, DI, ...) \
  bp=b; assert(0 == enc##CMD(&bp,be, LEN, __VA_ARGS__)); \
    printf("!! i=%i\n", bp-b); assert((bp-b)==(EI)); \
  bp=b; len=0; assert(CMD == deccmd(&bp,be, &len)); assert((DI)==(bp-b)); \
    assert(LEN == len);

  T_ROUND(RUN, 3,    2, 1, 'z'); assert(*bp == 'z');
  T_ROUND(RUN, 0x50, 3, 2, 'y'); assert(*bp == 'y');
  T_ROUND(ADD, 4,    5, 1, "test"); assert(0 == memcmp(bp, "test", 4));
  T_ROUND(CPY, 7,    2, 1, 5); assert(5 == decv(&bp,be, 0,0));
  T_ROUND(CPY, 7,    4, 1, 0x4000); assert(0x4000 == decv(&bp,be, 0,0));
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
// TODO: don't set end here
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

#define FP_ALLOC(FP, LEN) do { \
    (FP).len = LEN; (FP).t = malloc((LEN) * sizeof(uint32_t)); \
    ASSERT((FP).t, "OOM: FP"); \
    FP_init(&FP);              \
  } while(0) \


static inline void FP_init(FP* f) {
  for (size_t i=0; i < f->len; i++) f->t[i] = UINT32_MAX;
}
static inline void FP_free(FP* f) {
  if(f->t) { free(f->t); f->t = NULL; }
}

#define FP_FREE(NAME) free((NAME).t)
// calculate the fingerprint and set to i.
// Return the value (index) that was previously there.
static inline uint32_t FP_set(FP* f, A32* a, uint32_t i) {
  printf("!! FP_set i=%i\n", i);
  uint32_t fp = A32_fp(a, 3);
  printf("!!   FP_set fpi=%u fp=%u (0x%x)\n", fp % f->len, fp);
  uint32_t o = f->t[fp % f->len];
  printf("!!   FP_set oi=%u o=%u (0x%x)\n", o % f->len, o, o);
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

// window type
typedef struct _Win {
  uint8_t *sp, *ep; // start/end pointer to change
  uint8_t *s, *e;   // start/end of buffer
} Win;
static inline int Win_len(Win* w) { return w->ep - w->sp; }

// print window relative to s
static inline int Win_print(uint8_t* name, uint8_t* r, Win* w) {
  printf("%s{%i %i:%i %i}\n", name, w->s-r, w->sp-r,w->ep-r, w->e-r);
}

// Expand both windows as long as they are equal
// Requires: ws == we for both at the start
static inline void Win_expand(Win* a, Win* b) {
  printf("!! Win_expand: "); Win_print("a", a->s, a);
  printf("!!             "); Win_print("b", a->s, b);
  printf("!!              %i =? %i\n", *a->ep, *b->ep);
  while((a->ep < a->e) && (b->ep < b->e) && (*a->ep == *b->ep)) {
    printf("!!   aei=%i bei=%i\n", a->ep-a->s, b->ep-b->s);
    a->ep += 1; b->ep += 1;
  }
  if(a->ep == b->ep) return;
  a->sp -= 1; b->sp -= 1;
  while((a->sp >= a->s) && (b->sp >= b->s) && (*a->sp == *b->sp)) {
    printf("!!   asi=%i bsi=%i\n", a->sp-a->s, b->sp-b->s);
    a->sp -= 1; b->sp -= 1;
  }
  a->sp += 1; b->sp += 1;
  Win_print("!!   result left", a->s, a);
}



#ifdef TEST
void test_window() {
  printf("# test_window (c)\n");
  uint8_t* s = "01234567  01234567";
  Win a, b;

  // expand two windows from pre-set point
  #define TEXPAND(a_s, a_sp, a_e,   \
                  b_s, b_sp, b_e,   \
                  expect_a_sp, expect_a_ep, \
                  expect_b_sp, expect_b_ep) \
        a = (Win) { .s=s+a_s, .sp=s+a_sp, .ep=s+a_sp, .e=s+a_e }; \
        b = (Win) { .s=s+b_s, .sp=s+b_sp, .ep=s+b_sp, .e=s+b_e }; \
        Win_expand(&a, &b); \
        assert(a_s == a.s-s); assert(a_e == a.e-s); /*sanity*/ \
        assert(b_s == b.s-s); assert(b_e == b.e-s); /*sanity*/ \
        printf("!!  Win"); Win_print("a", s, &a); \
        printf("!!  Win"); Win_print("b", s, &b); \
        assert(expect_a_sp == a.sp-s); assert(expect_a_ep == a.ep-s); \
        assert(expect_b_sp == b.sp-s); assert(expect_b_ep == b.ep-s);

  // a=first 0-7, b=second 0-7
  TEXPAND(/*a.s=*/0, /*a.sp=*/0,  /*a.e=*/10,
          /*b.s=*/0, /*b.sp=*/10, /*b.e=*/20,
          /*expect_a_sp=*/0,  /*expect_a_ep=*/8,
          /*expect_b_sp=*/10, /*expect_b_ep=*/18);

  // a=first3-7, b=second3-7 (same result)
  TEXPAND(/*a.s=*/0, /*a.sp=*/3,  /*a.e=*/10,
          /*b.s=*/0, /*b.sp=*/13, /*b.e=*/20,
          /*expect_a_sp=*/0,  /*expect_a_ep=*/8,
          /*expect_b_sp=*/10, /*expect_b_ep=*/18);

  // same but boundary check (only goes to 6)
  TEXPAND(/*a.s=*/0, /*a.sp=*/3,  /*a.e=*/6, // change: 10 -> 6
          /*b.s=*/0, /*b.sp=*/13, /*b.e=*/20,
          /*expect_a_sp=*/0,  /*expect_a_ep=*/6,
          /*expect_b_sp=*/10, /*expect_b_ep=*/16);
  #undef TEXPAND
}
#endif

#ifdef TEST
int main() {
  printf("# TEST smol.c\n");
  test_encode_v();
  test_encode_cmds();
  test_fp();
  test_window();
  return 0;
}
#endif

//************************
//* Patch (decode) RDelta

// get the patch's resultant change length
static int rpatch_clen(uint8_t* xp, uint8_t* xe) {
  size_t len = 0;
  while(xp < xe) {
    int cmdlen; int cmd = deccmd(&xp,xe, &cmdlen);
    printf("!! + rpatch_clen %X len=%i\n", cmd, cmdlen);
    switch(cmd) {
      case RUN: xp += 1;
      case ADD: len += cmdlen; break;
      case CPY:
        len += cmdlen;
        if(decv(&xp,xe, 0,0) < 0) return -1;
        break;
      default: return -1;
    }
  }
  return len;
}

// apply an rdelta which consists of a command block and (raw) text block
// and optional base to get the change.
// (delta_cmds, delta_text, base?) -> change
static int l_rpatch(LS* L) {
  size_t xlen; uint8_t* xmds = (uint8_t*)luaL_checklstring(L, 1,   &xlen);
  size_t tlen; uint8_t* text = (uint8_t*)luaL_checklstring(L, 2,   &tlen);
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 3, "", &blen);
  printf("!! rpatch xlen=%i tlen=%i\n", xlen, tlen);
  printf("!!        blen=%i base=%s\n", blen, base);

  ASSERT(xlen >= 1, "#rdelta xmds == 0");
  uint8_t *xp = xmds, *xe = xmds+xlen;
  uint8_t *tp = text, *te = text+tlen;

  // decode the length of the final output
  int clen = rpatch_clen(xp,xe); ASSERT(clen >= 0, "clen");
  printf("!!       clen=%i\n", clen);

  if(clen == 0) { lua_pushstring(L, ""); return 1; }

  uint8_t* dec = malloc(blen + clen); ASSERT(dec, "OOM");
  memcpy(dec, base, blen);
  uint8_t *dp = dec + blen, *de=dec + blen + clen;

  uint8_t* error = "OOB error";
  while(xp < xe) {
    // x == command
    int cmdlen; int cmd = deccmd(&xp,xe, &cmdlen);
    switch (cmd) {
      case ADD:
        if((tp + cmdlen > te) || (dp + cmdlen > de)) goto error;
        memcpy(dp, tp, cmdlen); tp += cmdlen;
        break;
      case RUN:
        if((tp + 1 > te) || (dp + cmdlen > de)) goto error;
        memset(dp, *tp, cmdlen); tp += 1;
        break;
      case CPY:
        int raddr = decv(&xp,xe, 0,0); if(raddr < 0) goto error;
        size_t di = dp - dec;
        raddr = di - raddr - cmdlen;
        if(raddr < 0)           { error = "negative CPY"; goto error; }
        if(raddr + cmdlen > di) { error = "forward CPY";  goto error; }
        memcpy(dp, &dec[raddr], cmdlen);
        break;
      case -1: goto error;
      default: error = "unreachable"; goto error;
    }
    dp += cmdlen;
  }
  if((dp - dec - blen) != clen) {
    error = "incorrect change length"; goto error;
  }
  lua_pushlstring(L, dec+blen, clen);
  free(dec);
  return 1;
error:
  free(dec);
  luaL_error(L, error); return 0;
}

//************************
//* Create (encode) rdelta

// create an rdelta
// (change, base?) -> rxmds, rtext
static int l_rdelta(LS* L) {
  FP fp4 = {0};

  char* err = NULL;
  size_t clen; uint8_t* change = (uint8_t*)luaL_checklstring(L, 1, &clen);
  if(clen == 0) { lua_pushlstring(L, "\0", 1); return 1; }
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 2, "", &blen);
  printf("!! rdelta clen=%i change=%s\n", clen, change);
  printf("!!        blen=%i base=%s\n", blen, base);

  size_t dlen = blen + clen;
  uint8_t* dec = malloc(dlen); ASSERT(dec, "OOM");

  // we fail if the encoded length == change length
  size_t elen = dlen * 2;
  uint8_t* enc = malloc(elen); ASSERT(enc, "OOM");

  // run character and pointer
  uint8_t rc; uint8_t* rp;

  memcpy(dec, base, blen); memcpy(dec+blen, change, clen);

  // set up pointers. The ep and dp pointers are moved by
  // the sub-algorithms as we encode.
  uint8_t *ep=enc, *ee=enc+elen, *dp=dec+blen, *de=dec+dlen;

  // encode final change len
  if(encv(&ep,ee, clen)) goto error; // -> nil

  // ap=add pointer in dec.
  // ADD is the "fallback", we build up the bytes we want
  // to add and do it in one go immediately before other ops.
  uint8_t* ap = dec+blen;
  #define ENC_ADD() if(ap < dp) { \
    if(encADD(&ep,ee, dp-ap, ap)) goto error; /* -> nil */ \
  }

  Win wl, wr; // left and right windows
  #define WFIND(LI, RP) /*window find at fingerprint index*/    \
    wl = (Win) {.s=dec, .sp=dec+(LI), .ep=dec+(LI), .e=dp}; \
    wr = (Win) {.s=dp,  .sp=RP,       .ep=RP,       .e=de}; \
    Win_expand(&wl, &wr);

  // found like-windows. Encode wl (window left) as a copy
  #define WLEN(W)   Win_len(W)
  #define ENC_CPY() do { \
    ENC_ADD(); \
    encCPY(&ep,ee, Win_len(&wl), dp-wl.ep); \
    dp += Win_len(&wl); ap = dp; \
  } while(0)

  // CPY starting bytes and setup for copying ending bytes
  WFIND(0, dp);    if(gain(Win_len(&wl), blen) >= 2) { ENC_CPY(); }
  WFIND(blen, de); if(gain(Win_len(&wl), clen) >= 2) { de = wr.sp; }

  // fingerprint pointer and tables
  uint8_t* fpp = dec; uint32_t fpi;
  A32 a32 = {.end=de};
  FP_ALLOC(fp4, 99999); // TODO: use different prime

  while(dp < de) {
    printf("!!#### dec index=%i (dp=0x%p)\n", dp - dec, dp);
    for(;fpp < dp; fpp += 1) { // add finterprints we missed
      A32_start(&a32, fpp, de);
      FP_set(&fp4, &a32, fpp - dec);
    }
    printf("!!## Done adding dpp<de\n");

    // compute run length
    rc = *dp; rp=dp+1; while((rp < de) && (rc == *rp)) { rp += 1; }
    #define RUN_LEN() (rp - dp)
    #define ENC_RUN() do { \
      ENC_ADD();        \
      encRUN(&ep,ee, RUN_LEN(),rc); \
      dp += RUN_LEN(); ap = dp; \
    } while(0)

    // find window/s
    A32_start(&a32, fpp, de);
    wl.sp = dp; wl.ep = dp;
    fpi = FP_set(&fp4, &a32, fpp - dec); fpp += 1;
    if(fpi < UINT32_MAX) WFIND(fpi, dp);
    printf("!! DECISION: '%c' rlen=%i fp4=%i\n", rc, RUN_LEN(), Win_len(&wl));
    Win_print("!! fp4 win: ", dec, &wl);
    int wg = gain(Win_len(&wl), dp-wl.ep); // window gain
    if (wg > 1) {
      if     (gain(RUN_LEN(), 0) >= wg) ENC_RUN();
      else                              ENC_CPY();
    } else if(gain(RUN_LEN(), 0) > 1)   ENC_RUN();
    else dp += 1;
  }

  ENC_ADD();
  if(de < dec + dlen) // enc final matching block
    encCPY(&ep,ee, /*len*/(dec+dlen)-de, dp-(dec+blen));

  lua_pushlstring(L, enc, ep-enc);
  free(dec); free(enc);
  FP_free(&fp4);
  return 1;
error:
  free(dec); free(enc);
  FP_free(&fp4);
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


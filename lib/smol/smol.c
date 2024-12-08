
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

#define eprintf(...) fprintf(stderr, __VA_ARGS__)

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

#define MIN_PO2 8
#define MAX_PO2 27

#define MIN(A,B) ((A) < (B)) ? (A) : (B)
#define MAX(A,B) ((A) > (B)) ? (A) : (B)

// get the po2 that is greater than or equal to v
// (minimum 8, maximum 27)
static int po2(uint32_t v) {
  int po2 = 0;
  if(v >= (1<<16)) {
    po2 = 16;
    if(v > (1<<31)) return 31;
    if(v >= (1<<24)) po2 = 24;
  }
  else if(v >= (1<<8)) po2 = 8;
  while(v > (1 << po2)) { po2 += 1; }
  return po2;
}

// the previous prime for 2^8 to 2^27
// generated from po2prime.lua
uint32_t po2primes[] = {
  0xfb,       0x1fd,      0x3fd,      0x7f7,     // 8-11
  0xffd,      0x1fff,     0x3ffd,     0x7fed,    // 12-15
  0xfff1,     0x1ffff,    0x3fffb,    0x7ffff,   // 16-19
  0xffffd,    0x1ffff7,   0x3ffffd,   0x7ffff1,  // 20-23
  0xfffffd,   0x1ffffd9l, 0x3fffffb,  0x7ffffd9, // 24-27
};

// get a prime number just before the power of 2
static int po2prime(int po2) {
  po2 = MAX(MIN_PO2, MIN(po2, MAX_PO2));
  return po2primes[po2-MIN_PO2];
}

#ifdef TEST
static void test_po2() {
  printf("# test_po2 (c)\n");
  assert(1 == po2(2));
  assert(2 == po2(3)); assert(2 == po2(4));
  assert(3 == po2(5));
  assert(9  == po2(1<<9));
  assert(18 == po2(1<<18));
  assert(19 == po2(1<<19));
  assert(26 == po2(1<<26));
  assert(31 == po2(1<<31)); assert(31 == po2((1<<31) + 9999)); // max

  assert(0xfb      == po2prime(po2(2)));
  assert(0xfb      == po2prime(po2(0xff)));
  assert(0xffffd   == po2prime(po2(0xfffff)));
  assert(0x7ffffd9 == po2prime(po2(1<<30)));
  assert(0x7ffffd9 == po2prime(po2(1<<27)));
  assert(0x3fffffb == po2prime(po2(1<<26)));
}
#endif

//************************
//* 1.a RDelta Encode / Decode value

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
//* 1.b Encode / Decode Commands

// fingerprint struct
typedef struct _FP {
  uint32_t* t;
  size_t    len;
  size_t    tsz; // size in bytes
} FP;


// struct which holds data buffers and state of encoding/decoding.
// The buffers can be reused for relevant calls.
typedef struct _X {
  int fp4po2;

  uint8_t *xmd, *xp, *xe; size_t xmdsz;  // xmds buf, pointer, end (commands)
  uint8_t *txt, *tp, *te; size_t txtsz;  // txt buf, pointer, end (raw text)
  uint8_t *dec; size_t decsz;            // decoding buffer
  uint8_t *enc; size_t encsz;            // encoding buffer
  uint8_t *scr; size_t scrsz;            // scratch buffer
  FP fp4, fp8;
} X;

#define META_X "smol.X"
#define L_asX(L, I) ((X*)luaL_checkudata(L, I, META_X))

#define FREE_FIELD(X, F) \
  if((X).F##sz) { free((X).F); (X).F = NULL; (X).F##sz = 0; }
static void X_free(X* x) {
  FREE_FIELD(*x, xmd); FREE_FIELD(*x, txt);
  FREE_FIELD(*x, dec); FREE_FIELD(*x, enc);
  FREE_FIELD(*x, scr);
  FREE_FIELD(*x, fp4.t);
}
#define ALLOC_FIELD(X, F, SZ) do { \
    if((X).F##sz < (SZ)) {        \
      FREE_FIELD(X, F);           \
      (X).F = malloc(SZ);       \
      ASSERT((X).F, "OOM:"#F);  \
      (X).F##sz = SZ;           \
    } \
  } while(0)

static inline int deccmd(uint8_t** b, uint8_t* be, int* len) {
  if(*b >= be) return -1;
  uint8_t ch = **b; *b += 1;
  *len = 0x1F & ch; int cmd = 0xC0 & ch;
  if(0x20 & ch) *len = decv(b,be, *len,5);
  if(*len < 0) return -1;
  return cmd;
}
static inline int enccmd(uint8_t** b, uint8_t* be, int cmd, int clen) {
  if(*b >= be) return -1;
  if (clen > 0x1F) {
    **b = cmd | 0x20 | (0x1F & clen); *b += 1;
    return encv(b,be, clen >> 5);
  }
  **b = cmd | clen; *b += 1;
  return 0;
}

static inline int encRUN(X* x, int r, uint8_t ch) {
  DBG("encRUN len=%i '%c'\n", r, ch);
  if(enccmd(&x->xp,x->xe, RUN,r)) return -1;
  if(x->tp >= x->te)              return -1;
  *x->tp = ch; x->tp += 1;
  return 0;
}

static inline int encADD(X* x, int addlen, uint8_t* str) {
  DBG("encADD len=%i: %.*s\n", addlen, addlen, str);
  if(enccmd(&x->xp,x->xe, ADD,addlen)) return -1;
  if(x->tp + addlen >= x->te)          return -1;
  memcpy(x->tp, str, addlen); x->tp += addlen;
  return 0;
}

static inline int encCPY(X* x, int cpylen, int raddr) {
  assert(raddr >= 0);
  DBG("encCPY len=%i raddr=%i\n", cpylen, raddr);
  if(enccmd(&x->xp,x->xe, CPY,cpylen)) return -1;
  return encv(&x->xp,x->xe, raddr);
}

#ifdef TEST
static void test_encode_cmds() {
  printf("# test_encode_cmds (c)\n");
  int len;
  uint8_t b[32] = "\x43z";
  uint8_t *bp=b, *be=b+32;

  assert(RUN == deccmd(&bp,be, &len));
  assert(3 == len); assert(1 == bp-b);

  uint8_t t[32];
  X x = { .xp=b, .xe=b+32, .tp=t, .te=t+32, };

#define T_ROUND(CMD, LEN, EI, DI, ...) \
  x.xp=b; x.tp=t; assert(0 == enc##CMD(&x, LEN, __VA_ARGS__)); \
    printf("i=%i\n", x.xp-b); assert((x.xp-b)==(EI)); \
  x.xp=b; x.tp=t; len=0; assert(CMD == deccmd(&x.xp,x.xe, &len)); \
    assert((DI)==(x.xp-b)); \
    assert(LEN == len);

  T_ROUND(RUN, 3,    1, 1, 'z'); assert(*t == 'z');
  T_ROUND(RUN, 0x50, 2, 2, 'y'); assert(*t == 'y');
  T_ROUND(ADD, 4,    1, 1, "test"); assert(0 == memcmp(t, "test", 4));
  T_ROUND(CPY, 7,    2, 1, 5); assert(5 == decv(&x.xp,x.xe, 0,0));
  T_ROUND(CPY, 7,    4, 1, 0x4000); assert(0x4000 == decv(&x.xp,x.xe, 0,0));
#undef T_ROUND
}
#endif

//************************
//* 1.c: Addler32 Fingerprint Table

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
}

// perform the loops and return the fingerprint. Updates p, a and b
static inline int A32_fp(A32* a, int loops) {
  for(; loops > 0; loops--) {
    if(a->p >= a->end) break;
    a->a = (a->a + *a->p) % MOD_ADLER;
    a->b = (a->a +  a->b) % MOD_ADLER;
    a->p += 1;
  }
  return (a->b << 16) | a->a;
}

#define FP_ALLOC(X, F, LEN) do { \
    ALLOC_FIELD(X, F.t, (LEN) * sizeof(uint32_t)); \
    (X).F.len = LEN; \
    FP_init(&(X).F); \
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
  uint32_t fp = A32_fp(a, 3);
  uint32_t o = f->t[fp % f->len];
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
    printf("got r=%u (0x%x)\n", r, r); \
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
static inline void Win_expand(Win* wl, Win* wr) {
  Win l = *wl, r = *wr;
  while((l.ep < l.e) && (r.ep < r.e) && (*l.ep == *r.ep)) {
    l.ep += 1; r.ep += 1;
  }
  if(l.ep == r.ep) goto end;
  r.s = MAX(l.ep, r.s); // we may have gone past the start
  l.sp -= 1; r.sp -= 1;
  while((l.sp >= l.s) && (r.sp >= r.s) && (*l.sp == *r.sp)) {
    l.sp -= 1; r.sp -= 1;
  }
  l.sp += 1; r.sp += 1;
end:
  wl->sp = l.sp; wl->ep = l.ep;
  wr->sp = r.sp; wr->ep = r.ep;
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
        DBG(" Win"); Win_print("a", s, &a); \
        DBG(" Win"); Win_print("b", s, &b); \
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

//************************
//* 1.d: Patch (decode) RDelta

// get the patch's resultant change length
static int rcmdlen(uint8_t* xp, uint8_t* xe) {
  int len = 0; while(xp < xe) {
    int cmdlen; int cmd = deccmd(&xp,xe, &cmdlen);
    len += cmdlen;
    switch(cmd) {
      case RUN:
      case ADD: break;
      case CPY:
        if(decv(&xp,xe, 0,0) < 0) return -1;
        break;
      default: return -1;
    }
  }
  return len;
}

// apply an rdelta which consists of a command block and (raw) txt block
// and optional base to get the change.
// (delta_cmds, delta_txt, X, base?) -> change
static int l_rpatch(LS* L) {
  DBG("############ rpatch\n");
  size_t xlen; uint8_t* xmds = (uint8_t*)luaL_checklstring(L, 1,   &xlen);
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 2,   &tlen);
  X* x = L_asX(L, 3);
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 4, "", &blen);

  ASSERT(xlen >= 1, "#rdelta xmds == 0");
  uint8_t *xp = xmds, *xe = xmds+xlen;
  uint8_t *tp = txt, *te = txt+tlen;

  // decode the length of the final output
  int clen = rcmdlen(xp,xe); ASSERT(clen >= 0, "clen");
  DBG("dlen=%i xlen=%i tlen=%i\n", blen+clen, xlen, tlen);

  if(clen == 0) { lua_pushstring(L, ""); return 1; }

  ALLOC_FIELD(*x, dec, blen + clen); uint8_t* dec = x->dec;
  memcpy(dec, base, blen);
  uint8_t *dp = dec + blen, *de=dec + blen + clen;

  uint8_t* error = "OOB error";
  while(xp < xe) {
    // x == command
    int cmdlen; int cmd = deccmd(&xp,xe, &cmdlen);
    switch (cmd) {
      case ADD:
        DBG("ADD len=%i ti=%i  di=%i\n", cmdlen, tp-txt, dp-dec);
        if((tp + cmdlen > te) || (dp + cmdlen > de)) goto error;
        memcpy(dp, tp, cmdlen); tp += cmdlen;
        break;
      case RUN:
        DBG("RUN len=%i ti=%i  di=%i\n", cmdlen, tp-txt, dp-dec);
        if((tp + 1 > te) || (dp + cmdlen > de)) goto error;
        memset(dp, *tp, cmdlen); tp += 1;
        break;
      case CPY:
        DBG("CPY len=%i ti=%i  di=%i\n", cmdlen, tp-txt, dp-dec);
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
  return 1;
error:
  luaL_error(L, error); return 0;
}

//************************
//* 1.e: Create (encode) rdelta

// create an rdelta
// (change, x, base?) -> (cmds, txt)
static int l_rdelta(LS* L) {
  DBG("############ rdelta\n");
  char* err = NULL;
  size_t clen; uint8_t* change = (uint8_t*)luaL_checklstring(L, 1, &clen);
  X* x = L_asX(L, 2);
  if(clen == 0) {
    lua_pushlstring(L, "\0", 1);
    lua_pushstring(L, "");
    return 2;
  }
  size_t blen; uint8_t* base = (uint8_t*)luaL_optlstring(L, 3, "", &blen);
  size_t dlen = blen + clen;

  ALLOC_FIELD(*x, dec,  dlen); uint8_t* dec  = x->dec;
  ALLOC_FIELD(*x, xmd,  dlen); uint8_t* xmd  = x->xmd;
  ALLOC_FIELD(*x, txt, dlen); uint8_t* txt = x->txt;
  x->xp = xmd;  x->xe = xmd+dlen;
  x->tp = txt; x->te = txt+dlen;

  // set up pointers which are moved by the sub-algorithms as we encode.
  uint8_t *dp=dec+blen, *de=dec+dlen; // decode pointer

  // run character and pointer
  uint8_t rc; uint8_t* rp; size_t rl;

  // move the base+change into dec
  memcpy(dec, base, blen); memcpy(dec+blen, change, clen);

  // ap=add pointer in dec.
  // ADD is the "fallback", we build up the bytes we want
  // to add and do it in one go immediately before other ops.
  uint8_t* ap = dec+blen;
  #define ENC_ADD(TO) if(ap < (TO)) { \
    if(encADD(x, (TO)-ap, ap)) goto error; /* -> nil */ \
  }

  Win wl, wr; // left and right windows
  #define WFIND(LI, RP) do { /*window find at fingerprint index*/    \
    wl = (Win) {.s=dec, .sp=dec+(LI), .ep=dec+(LI), .e=dp}; \
    wr = (Win) {.s=ap,  .sp=RP,       .ep=RP,       .e=de}; \
    Win_expand(&wl, &wr); \
  } while(0)

  // found like-windows. Encode wl (window left) as a copy
  #define WLEN(W)   Win_len(W)
  #define ENC_CPY() do { \
    ENC_ADD(/*TO*/wr.sp); \
    if(encCPY(x, Win_len(&wl), wr.sp - wl.ep)) goto error; \
    DBG("  CPY: %.*s\n", Win_len(&wl), wl.sp); \
    dp = wr.ep; ap = dp; \
  } while(0)

  // CPY starting bytes and setup for copying ending bytes
  WFIND(0,    dp); if(gain(Win_len(&wl), blen) >= 2) { ENC_CPY(); }
  WFIND(blen, de); if(gain(Win_len(&wl), clen) >= 2) { de = wr.sp; }

  // fingerprint pointer and tables
  uint8_t* fpp = dec; uint32_t fpi;
  A32 a32 = {.end=de};

  // 4 byte match is valuable up to 2^14 bytes away
  FP_ALLOC(*x, fp4, po2prime(po2(MIN(0xff, MAX(dlen, x->fp4po2)))));
  FP* fp4 = &x->fp4;

  while(dp < de) {
    for(; fpp < dp; fpp += 1) { // add finterprints we missed
      A32_start(&a32, fpp, de);
      FP_set(fp4, &a32, fpp - dec);
    }

    // compute run length
    rc = *dp; rp=dp+1; while((rp < de) && (rc == *rp)) { rp += 1; }
    rl = rp - dp; // run length
    #define ENC_RUN(LEN) do { \
      ENC_ADD(dp);        \
      if(encRUN(x, LEN,rc)) goto error; \
      dp += LEN; ap = dp; \
    } while(0)

    // find window/s
    A32_start(&a32, fpp, de);
    wl.sp = dp; wl.ep = dp;
    fpi = FP_set(fp4, &a32, fpp - dec);
    fpp += 1;
    wl.sp = NULL; wl.ep = NULL;
    if(fpi < UINT32_MAX) WFIND(fpi, dp);
    int wg = gain(Win_len(&wl), /*raddr*/wr.sp - wl.ep); // window gain
    if (wg > 1) {
      if     (gain(rl, 0) >= wg) ENC_RUN(rl);
      else                       ENC_CPY();
    } else if(gain(rl, 0) > 1)   ENC_RUN(rl);
    else dp += 1;
  }

  ENC_ADD(dp);
  if(de < dec + dlen) // enc final matching block
    encCPY(x, /*len*/(dec+dlen) - de, /*raddr*/dp - (dec+blen));

  lua_pushlstring(L, xmd, x->xp - xmd);
  lua_pushlstring(L, txt, x->tp - txt);
  return 2;
error:
  ASSERT(!err, err);
  return 0;
}

static int l_X_free(LS* L) { X_free(L_asX(L, 1)); return 0; }
static int l_createX(LS* L) {
  X x = {0};
  lua_getfield(L, 1, "fp4po2"); x.fp4po2 = luaL_checkinteger(L, -1);
  X* r = (X*)lua_newuserdata(L, sizeof(X));
  luaL_setmetatable(L, META_X);
  *r = x;
  return 1;
}

// (xmds) -> (changelen)
static int l_rcmdlen(LS *L) {
  size_t xlen; uint8_t* xmds = (uint8_t*)luaL_checklstring(L, 1, &xlen);
  lua_pushinteger(L, rcmdlen(xmds, xmds+xlen));
  return 1;
}

//************************
//* 2.a Huffman Utils

// Bit IO, optimized for reading by using least-significant-bit first
typedef struct _BIO {
  uint8_t *bp, *be; // buffer pointer, buffer end
  int c, bits; // current byte, current bits in c
} BIO;

// read the specific number of bits LSB first
static int BIOread(BIO* io, int bits) {
  int out = 0, readBits;
  while(bits) {
    if(io->bits) {
      readBits = MIN(bits, io->bits);
      out = (out << readBits) | (((1 << readBits) - 1) & io->c);
      io->bits -= readBits;
      bits -= readBits;
      io->c = io->c >> readBits;
    } else {
      if(io->bp >= io->be) return -1;
      io->c = *io->bp; io->bits = 8; io->bp += 1;
    }
  }
  printf("!! BIORead %i (0x%x) c=0x%x bits=%i\n",
         out, out, io->c, io->bits);
  return out;
}

// push available character.
// Invariant: MUST check io->bits first.
static inline int BIOpush(BIO* io) {
  if(io->bp >= io->be) return -1;
  *io->bp = io->c; io->bp += 1;
  io->bits = 0; io->c = 0;
  return 0;
}

// write the specific number of bits LSB first
static int BIOwrite(BIO* io, int v, int bits) {
  assert(bits <= 8);
  int vbits = 0, writeBits, tmp;
  while(bits) {
    if(io->bits >= 8) {
      printf("!! io->bits == 8\n");
      assert(io->bits == 8);
      if(BIOpush(io)) return -1;
    } else {
      writeBits = MIN(bits, 8 - io->bits);
      printf("!! io->bits=%i, writeBits=%i\n", io->bits, writeBits);
      tmp = (1 << writeBits) - 1; // mask
      tmp = (tmp << vbits) & v;   // piece of value that we put in c
      // shift left or right depending on where it needs to go in c
      if(vbits >= io->bits) tmp = tmp >> (vbits - io->bits);
      else                  tmp = tmp << (io->bits - vbits);
      io->c = io->c | tmp;
      io->bits += writeBits;
      bits -= writeBits;
    }
    writeBits = MIN(io->bits, bits);
  }
  printf("!! BIOwrite 0x%x end c=0x%x bits=%i\n",
         v, io->c, io->bits);
  return 0;
}

#ifdef TEST
void test_BIO() {
  printf("# test_BIO (c)\n");
  uint8_t dat[] = {0xF5, 0x81};
  BIO io = {.bp = dat, .be=dat+2};
  // 5 == 0101
  assert(1 == BIOread(&io, 2));
  assert(1 == BIOread(&io, 2));
  assert(0xF == io.c); assert(4 == io.bits);
  // F = 0b1111 (3=0b11)
  assert(1 == BIOread(&io, 1)); assert(3 == BIOread(&io, 2));
  // last of F and first of 81 (1)
  assert(3    == BIOread(&io, 2));
  assert(0x40 == BIOread(&io, 7));
  assert(-1   == BIOread(&io, 1));

  // write
  io = (BIO) {.bp = dat, .be=dat+2};
  memset(dat, 0, 2); assert(0 == dat[0]); assert(0 == dat[1]);
  BIOwrite(&io, 1,    1); assert(1 == io.c);    assert(1 == io.bits);
  BIOwrite(&io, 1,    1); assert(3 == io.c);    assert(2 == io.bits);
  BIOwrite(&io, 0x20, 6); assert(0x83 == io.c); assert(8 == io.bits);
    assert(dat == io.bp);
  BIOwrite(&io, 1,    1); assert(1 == io.c);    assert(1 == io.bits);
    assert(dat+1 == io.bp);
    assert(0x83 == dat[0]);
  BIOpush(&io);
    assert(0x83 == dat[0]); assert(1 == dat[1]);

  // read what we just wrote
  io = (BIO) {.bp = dat, .be=dat+2};
  assert(3 == BIOread(&io, 4)); assert(8 == BIOread(&io, 4));
  assert(1 == BIOread(&io, 8));
}
#endif

typedef struct _HN { // Huff Node
  struct _HN *l, *r; // parent/left/right indexes (root p=NULL)
  int32_t count; // prevelance of this value
  int v; // value
  // the 1's and 0's and how many there are
  uint64_t bits;
  uint8_t nbits;
} HN;

#define HTREE_SZ (0x100 * 3)
typedef struct _HT { // Huff Tree
  HN* root;
  HN n[HTREE_SZ]; uint32_t used;
} HT;

void spaces(int n) { while(n) { printf(" "); n -= 1; } }
void HN_printdfs(HN* n, int depth) {
  if(!n) { printf("<null root>\n"); return; }
  printf("v=%i '%c' (count=%i)\n", n->v, n->v, n->count);
  if(n->l) { spaces(depth); printf("< "); HN_printdfs(n->l, depth+1); }
  if(n->r) { spaces(depth); printf("> "); HN_printdfs(n->r, depth+1); }
}

#define SWAP(T, A, B) do { \
    printf("!!  SWAP: ('%c', '%c') -> ", A, B); \
    T _swap_tmp = A; A = B; B = _swap_tmp; \
    printf("('%c', '%c')\n", A, B); \
  } while(0)

#define PARENT(N) (N / 2)
#define LEFT(N)   ((N * 2) + 1)
#define RIGHT(N)  ((N * 2) + 2)

typedef struct _IHeap { // minheap of indexes into HT.n
  uint32_t* a;  // array of indexes into HT.n
  uint32_t len; // lenth of array
} IHeap;

void IHeap_print(HT* ht, IHeap* h) {
  for(int i=0; i < h->len; i++) {
    int ix = h->a[i]; int v = ht->n[ix].v;
    printf("!!   heap[%i] v=%x '%c' (count=%i)\n",
                       i,    v,  v,  ht->n[ix].count);
  }
}

// percolate the node at ht.n[h.arr[i]] up (towards root)
static void HT_percolateup(HT* ht, IHeap* h, uint32_t i) {
  HN* nodes = ht->n;
  uint32_t* indexes = h->a;
  while(i > 0) {
    uint32_t p = PARENT(i);
    uint32_t ci = indexes[i], pi = indexes[p]; // child/parent node idx
    // if min is parent, we are done
    printf("!!   percolateup %i: l=%i r=%i\n",
                             i, nodes[pi].count, nodes[ci].count);
    if(nodes[pi].count <= nodes[ci].count) break;
    printf("!!   + swapping\n");
    indexes[i] = pi; indexes[p] = ci; // swap
    i = p;
  }
}

// percolate the first node "down" (from root)
static void HT_percolatedown(HT* ht, IHeap* h, uint32_t hi) {
  printf("!! percolatedown hi=%i nodes=%p\n", hi, ht->n);
  uint64_t i = 0;    uint32_t tmp;
  HN* nodes = ht->n; uint32_t* nidxs = h->a;
  while(LEFT(i) <= hi) {
    uint64_t li = LEFT(i), ri = RIGHT(i); // left/right indexes
    uint32_t ni = nidxs[i]; // node index (into ht.nodes)
    uint32_t nc = nodes[ni].count; // node count
    printf("!! loop i=%i (li=%i ri=%i) ni='%c' nc=%i\n",
                       i,    li,   ri,     ni,    nc);
    uint32_t lni = nidxs[li], rni; // left/right node indexes
    if((ri <= hi) && (nodes[nidxs[ri]].count < nc)) {
      // right exists and is smaller than node count -- check all
      printf("!!   right\n");
      rni = nidxs[ri];
      if(nodes[lni].count < nodes[rni].count) { // left is smallest
        nidxs[i] = lni; nidxs[li] = ni; i = li; // swap i <-> left, go left
      } else { // right is smallest
        nidxs[i] = rni; nidxs[ri] = ni; i = ri; // swap i <->right, go right
      }
    } else if(nodes[lni].count < nc) { // right is not smaller, check left
      printf("!!   left\n");
      nidxs[i] = lni; nidxs[li] = ni; i = li;
    } else break; // node is smallest, done
  }
  printf("!! percolatedown DONE\n");
}

// pop index of minimum value from heap h
static inline uint32_t HT_heappop(HT* ht, IHeap* h) {
  assert(h->len >= 1);
  uint32_t ni = h->a[0];
  h->a[0] = h->a[h->len - 1];
  HT_percolatedown(ht, h, h->len - 2);
  h->len -= 1;
  return ni;
}

static inline void HT_heappush(HT* ht, IHeap* h, uint32_t hti) {
  uint32_t* nidxs = h->a;
  nidxs[h->len] = hti;
  HT_percolateup(ht, h, h->len);
  h->len += 1;
}

#define HLEN 256
static inline void hheap(HT* ht, IHeap* h, uint8_t* bp,uint8_t* be) {
  uint32_t* nidxs = h->a;
  ht->used = HLEN;
  memset(ht->n, 0, HTREE_SZ * sizeof(HN));
  printf("!! started htree\n");
   for(int i=0; i < HLEN; i++) {
    nidxs[i] = i; ht->n[i].v = i;
  }
  printf("!!   nidxs HLEN=%i [0]=%i [HLEN-1]=%i\n", HLEN, nidxs[0], nidxs[HLEN-1]);
  for(; bp < be; bp++) ht->n[*bp].count += 1; // count freq of each byte

  // initialize heap with zero-count nodes removed
  h->len = 0;
  for(int i=0; i < HLEN; i++) {
    if(ht->n[i].count > 0) { nidxs[h->len] = i; h->len += 1; }
  }
  printf("!! after init:\n");
  IHeap_print(ht, h);

  // heapify by expanding the size of the BT 1 node at a time, fixing it
  printf("!! doing heapify:\n");
  for(int i=1; i < h->len; i++) HT_percolateup(ht, h, i);

  printf("!! after heapify:\n");
  IHeap_print(ht, h);
}

#ifdef TEST
static void test_IHeap() {
  HT ht;
  uint32_t nidxs[HLEN]; IHeap h = {.a = nidxs};
  uint8_t* dat = "AAAA   zzzz;;";
  hheap(&ht, &h, dat, dat+strlen(dat));
  assert(ht.n['A'].count == 4); assert(ht.n['A'].v == 'A');
  assert(ht.n[' '].count == 3);
  assert(h.len == 4);
  assert(h.a[0] == ';'); // smallest
  assert(HT_heappop(&ht, &h) == ';');
  assert(h.a[0] == ' '); assert(h.len == 3);
  printf("!! after pop\n");
  IHeap_print(&ht, &h);
  HT_heappush(&ht, &h, ';');
  assert(h.a[0] == ';'); assert(h.len == 4);
  printf("!! IHeap done\n");
  IHeap_print(&ht, &h);
  assert(false);
}
#endif

// create huffman tree
static inline HT htree(uint8_t* bp,uint8_t* be) {
  HT ht;
  uint32_t nidxs[HLEN]; IHeap h = {.a = nidxs};
  hheap(&ht, &h, bp,be);

  if(!h.len) return ht; // empty huffman tree

  // build the huffman tree
  while(h.len > 1) {
    size_t len = h.len;
    printf("!! building tree heaplen=%i\n", len);
    HN *l = &ht.n[HT_heappop(&ht, &h)];
    HN *r = &ht.n[HT_heappop(&ht, &h)];
    printf("!!   got l='%c' (c=%i) r='%c' (c=%i) heaplen=%i\n",
                 l->v, l->count, r->v, r->count,     h.len);
    IHeap_print(&ht, &h);
    ht.n[ht.used] = (HN) {
      .l = l, .r = r, .count = l->count + r->count, .v = -1
    };
    printf("!!   added node count=%i\n", ht.n[ht.used].count);
    // heap push
    h.a[h.len] = ht.used; HT_percolateup(&ht, &h, h.len);
    ht.used += 1;
    h.len += 1;
    IHeap_print(&ht, &h);
  }
  ht.root = &ht.n[HT_heappop(&ht, &h)];
  HN_printdfs(ht.root, 0);
  assert(false);
  return ht;
  #undef HLEN
}

// encode a huffman tree into bytestream.
// leaf: write 1 + code (8 bits), else write 0
static inline void writeTree(BIO* b, HN* hn) {
  if(hn->v >= 0) {
    BIOwrite(b, 1, /*bits*/1); BIOwrite(b, hn->v, /*bits*/ 8);
  } else BIOwrite(b, 0, /*bits*/ 1);
}

// decode a huffman tree from b into ht
// static inline HN* readTree(BIO* b, HT* ht, uint64_t bits, uint8_t nbits) {
//   assert(ht->len < HTREE_SZ);
//   assert(b->bp < b->be);
//   HN* np = &ht->n[ht->len]; ht->len += 1;
//   if(BIOread(b, 1)) *np = (HN) {
//     .v = BIOread(b, 8), .bits = bits, .nbits = nbits
//   }; else *np = (HN) {
//     .l = readTree(b, ht,  bits << 1,      nbits + 1),
//     .r = readTree(b, ht, (bits << 1) + 1, nbits + 1),
//     .v = -1,
//   };
//   return np;
// }

#ifdef TEST
static void test_HT() {
  printf("# test_HT (c)\n");
  uint8_t* dat = "AAAA   zzzz;;";
  HT ht = htree(dat, dat + strlen(dat));
  eprintf("!! tree\n");
  assert(false);
}
#endif


//************************
//* 3.a Lua Bindings (and run test)

#ifdef TEST
int main() {
  printf("# TEST smol.c\n");
  test_po2();
  test_encode_v();
  test_encode_cmds();
  test_fp();
  test_window();
  test_BIO();
  test_IHeap();
  test_HT();
  return 0;
}
#endif

static const struct luaL_Reg smol_sys[] = {
  {"createX", l_createX},
  {"rpatch", l_rpatch}, {"rdelta", l_rdelta},
  {"rcmdlen", l_rcmdlen},
  {NULL, NULL}, // sentinel
};


#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_smol_sys(LS *L) {
  luaL_newlib(L, smol_sys);

  luaL_newmetatable(L, META_X);
    L_setmethod(L, "__gc",   l_X_free);
  lua_setfield(L, -2, "X");

  return 1;
}


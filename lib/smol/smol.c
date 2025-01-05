
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

#define DBG(...) printf("!D! " __VA_ARGS__)
// #define DBG(...)

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


//************************
//* 1.a RDelta Encode / Decode value

// decode value from bytes. v: current value, s: current shift
static inline int decv(uint8_t** b, uint8_t* be, int v, int s) {
  while((*b < be) && (0x80 & **b)) {
    v = ((0x7F & **b) << s) | v;
    s += 7; *b += 1;
  }
  if(*b >= be) return -1;
  v = (**b << s) | v; *b += 1;
  return v;
}

// encode value to bytes. v: current value, s: current shift
static inline int encv(uint8_t** b, uint8_t* be, int v) {
  while((*b < be) && (v > 0x7F)) {
    **b = 0x80 | v; v = v >> 7; *b += 1;
  }
  if(*b >= be) return -1;
  **b = v; *b += 1;
  return 0;
}



//************************
//* 1.b Encode / Decode Commands

// fingerprint struct
typedef struct _FP {
  uint32_t* t;
  size_t    len;
  size_t    tsz; // size in bytes
} FP;

// huffman bits: 1's and 0's and how many there are
typedef struct _HB {
  uint8_t nbits;
  uint64_t bits;
} HB;

// Huffman Tree Node
typedef struct _HN {
  struct _HN *l, *r; // parent/left/right indexes (root p=NULL)
  int32_t count; // prevelance of this value
  int v; // value
  HB hb;
} HN;

#define HTREE_SZ (0x100 * 3)
typedef struct _HT { // Huffman Tree
  HN* root;
  uint32_t used;
  HN n[HTREE_SZ];
  bool invalid;
} HT;

// struct which holds data buffers and state of encoding/decoding.
// The buffers can be reused for relevant calls.
typedef struct _X {
  int fp4po2;

  uint8_t *xmd, *xp, *xe; size_t xmdsz;  // xmds buf, pointer, end (commands)
  uint8_t *txt, *tp, *te; size_t txtsz;  // txt buf, pointer, end (raw text)
  uint8_t *dec; size_t decsz;            // decoding buffer
  FP fp4, fp8;
  HT ht;
  HB hbs[256];
} X;

#define META_X "smol.X"
#define L_asX(L, I) ((X*)luaL_checkudata(L, I, META_X))

// free field if it's been allocated
#define FREE_FIELD(X, F) \
  if((X).F##sz) { free((X).F); (X).F = NULL; (X).F##sz = 0; }

static void X_free(X* x) {
  FREE_FIELD(*x, xmd); FREE_FIELD(*x, txt);
  FREE_FIELD(*x, dec);
  FREE_FIELD(*x, fp4.t);
}

// allocate field if it's not large enugh
#define ALLOC_FIELD(X, F, SZ) do { \
    if((X).F##sz < (SZ)) {         \
      FREE_FIELD(X, F);            \
      (X).F = malloc(SZ);          \
      ASSERT((X).F, "OOM:"#F);     \
      (X).F##sz = SZ;              \
    }                              \
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

  // decode the length of the final output (called "change")
  int clen = rcmdlen(xp,xe);
  DBG("clen=%i dlen=%i xlen=%i tlen=%i\n", clen, blen+clen, xlen, tlen);
  ASSERT(clen >= 0, "invalid clen");

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
// (change, x, base?) -> (cmds, raw)
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
  ALLOC_FIELD(*x, txt, dlen); uint8_t* raw = x->txt;
  x->xp = xmd;  x->xe = xmd+dlen;
  x->tp = raw; x->te = raw+dlen;

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
  lua_pushlstring(L, raw, x->tp - raw);
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
  int used; // used bits in *bp
} BIO;

// read 1 bit (most-significant bit first)
static int BIOread1(BIO* io) {
  if(io->used == 8) {
    if(io->bp == io->be) return -1;
    io->bp += 1; io->used = 0;
  }
  io->used += 1;
  return 1 & (*io->bp >> (8 - io->used));
}

// read 8 bits (most-significant bit first)
static int BIOread8(BIO* io) {
  uint8_t* bp = io->bp;
  if(bp == io->be) return -1;
  io->bp = bp + 1;
  int used = io->used;
  if(used == 8) return *(bp+1);
  return 0xFF & ((*bp << used) | (*(bp+1) >> (8 - used)));
}

// write n bits (most-significant bit first)
static int BIOwrite(BIO* io, uint8_t nbits, uint64_t c) {
  int used = io->used; uint8_t *bp = io->bp, *be = io->be;
  while(nbits >= 8) {
    if(bp >= be) return -1;
    nbits -= 8; uint8_t ch = c >> nbits;
             *bp |= ch >> used;
    bp += 1; *bp  = ch << (8 - used);
  }
  if(used + nbits > 8) {
    if(bp >= be) return -1;
    uint8_t rem = 8 - used; // remaining bits in this byte
    c &= (1 << nbits) - 1;
    if(rem > nbits) {
      *bp |= c << (rem - nbits);
    } else {
      *bp |= c >> (nbits - rem);
    }
    nbits -= rem; bp += 1; used = 0;
  }
  if(nbits) {
    c &= (1 << nbits) - 1;
    *bp |= c << (8 - used - nbits);
    used += nbits;
  }
  io->bp = bp;
  io->used = used;
  return 0;
}
#undef WRITE8

// printf(...) to (char**S, char*E), returns -1 on failure
#define FMT(S,E, ...) do { \
    /*printf("FMT:"); printf(__VA_ARGS__);*/ \
    size_t FMT_avail = (E)-*(S); \
    int FMT_wrote = snprintf(*(S), FMT_avail, __VA_ARGS__); \
    /*printf("!! FMT avail=%i wrote=%i\n", FMT_avail, FMT_wrote);*/ \
    if((FMT_wrote < 0) || (FMT_avail < FMT_wrote)) return -1; \
    *(S) += FMT_wrote; \
  } while(0)

int spaces(uint8_t** s, uint8_t* e, int n) {
  if(n > e-*s) return -1;
  memset(*s, ' ', n); *s += n;
}
int HN_fmt(uint8_t** s,uint8_t* e, HN* n) {
  if(!n) { FMT(s,e, "(null root)\n"); return 0; }
  int nbits = n->hb.nbits, bits = n->hb.bits;
  if(n->v >= 0) {
    FMT(s,e, "(0x%x '%c' ", n->v, n->v);
    if(nbits > e-*s) return -1;
    while(nbits > 0) {
      nbits -= 1; **s = (1 & (bits >> nbits)) ? '1' : '0'; *s += 1;
    }
    FMT(s,e, " #%i\n", n->count);
  }
  else          FMT(s,e, "(%i)\n", n->hb.nbits);
  if(n->l) { spaces(s,e, 2*n->hb.nbits); FMT(s,e, "<"); HN_fmt(s,e, n->l); }
  if(n->r) { spaces(s,e, 2*n->hb.nbits); FMT(s,e, ">"); HN_fmt(s,e, n->r); }
}
int HN_printdfs(HN* n) {
  uint8_t buf[8192]; uint8_t* s = buf;
  if(HN_fmt(&s, s+8192, n)) {
    printf("!! HN_fmt error!!\n");
    return -1;
  }
  printf("HTREE (%i):\n%.*s", s-buf, s-buf, buf);
}

#define PARENT(N) (N / 2)
#define LEFT(N)   ((N * 2) + 1)
#define RIGHT(N)  ((N * 2) + 2)

#define HLEN 256
typedef struct _Heap { // minheap of node.count
  HN* a[HLEN];  // array of nodes
  uint32_t len; // lenth of array
} Heap;

void Heap_print(HT* ht, Heap* h) {
  for(int i=0; i < h->len; i++) { HN* n = h->a[i]; }
}

// percolate the node at ht.n[h.arr[i]] up (towards root)
static void HT_percolateup(HT* ht, Heap* h, uint32_t i) {
  HN** heap = h->a;
  while(i > 0) {
    uint32_t p = PARENT(i);
    HN *cn = heap[i], *pn = heap[p]; // child/parent node idx
    // if min is parent, we are done
    if(pn->count <= cn->count) break;
    heap[p] = cn; heap[i] = pn; // swap
    i = p;
  }
}

// percolate the first node "down" (from root)
static void HT_percolatedown(HT* ht, Heap* h, int32_t hi) {
  HN** heap = h->a;
  int64_t i = 0; // i is index into nidxs
  while(LEFT(i) <= hi) {
    uint64_t li = LEFT(i), ri = RIGHT(i); // left/right indexes into nidxs
    HN *n = heap[i], *ln = heap[li], *rn;
    if((ri <= hi) && (heap[ri]->count < n->count)) {
      // right exists and is smaller than node count -- check all
      rn = heap[ri];
      if(ln->count < rn->count) { // left is smallest
        heap[i] = ln; heap[li] = n; i = li; // swap i <-> left, go left
      } else { // right is smallest
        heap[i] = rn; heap[ri] = n; i = ri; // swap i <-> right, go right
      }
    } else if(ln->count < n->count) { // right is not smaller, check left
      heap[i] = ln; heap[li] = n; i = li;
    } else break; // node is smallest, done
  }
}

// pop index of minimum value from heap h
static inline HN* HT_heappop(HT* ht, Heap* h) {
  assert(h->len >= 1);
  HN* n = h->a[0];
  h->a[0] = h->a[h->len - 1];
  HT_percolatedown(ht, h, h->len - 2);
  h->len -= 1;
  return n;
}

static inline void HT_heappush(HT* ht, Heap* h, HN* n) {
  h->a[h->len] = n;
  HT_percolateup(ht, h, h->len);
  h->len += 1;
}

static inline void hheap(HT* ht, Heap* h, uint8_t* bp,uint8_t* be) {
  HN** heap = h->a;
  ht->used = HLEN;
  memset(ht->n, 0, HTREE_SZ * sizeof(HN));
   for(int i=0; i < HLEN; i++) {
    heap[i] = &ht->n[i]; ht->n[i].v = i;
  }
  for(; bp < be; bp++) ht->n[*bp].count += 1; // count freq of each byte

  // initialize heap with zero-count nodes removed
  h->len = 0;
  for(int i=0; i < HLEN; i++) {
    if(ht->n[i].count > 0) { heap[h->len] = &ht->n[i]; h->len += 1; }
  }

  // heapify by expanding the size of the BT 1 node at a time, fixing it
  for(int i=1; i < h->len; i++) HT_percolateup(ht, h, i);
}


static inline void HT_calcbits(HN* hn, uint64_t bits, uint8_t nbits) {
  // printf("!! ... in calcbits\n");
  hn->hb = (HB) {.bits = bits, .nbits = nbits};
  if(hn->v < 0) {
    // printf("!!"); spaces(2 + nbits); printf("<\n");
    HT_calcbits(hn->l,  bits << 1,      nbits + 1);
    // printf("!!"); spaces(2 + nbits); printf(">\n");
    HT_calcbits(hn->r, (bits << 1) + 1, nbits + 1);
  }
}

// create huffman tree
#define HNODE(L, R) \
  (HN) { .l = L, .r = R, .count = (L)->count + (R)->count, .v = -1 }

static inline void htree(HT* ht, uint8_t* bp,uint8_t* be) {
  Heap h; *ht = (HT){0};
  hheap(ht, &h, bp,be);
  if(!h.len) return; // empty huffman tree

  // build the huffman tree
  while(h.len > 1) {
    HN *l = HT_heappop(ht, &h);
    HN *r = HT_heappop(ht, &h);
    ht->n[ht->used] = HNODE(l, r);
    HT_heappush(ht, &h, &ht->n[ht->used]);
    ht->used += 1;
  }
  ht->root = HT_heappop(ht, &h);
  if(ht->root->v >= 0) {
    // fix root-only (aka single-value) tree
    ht->n[ht->used] = HNODE(ht->root, ht->root);
    ht->root = &ht->n[ht->used]; ht->used += 1;
  }
}

// encode a huffman tree into bytestream.
// leaf: write 1 + code (8 bits), else write 0 and the branches
static inline int encodeTree(BIO* b, HN* hn) {
  if(hn->v >= 0) {
    printf("!!   encodeTree v=%x '%c'\n", hn->v, hn->v);
    BIOwrite(b,1, 1);
    return BIOwrite(b,8, hn->v);
  }
  assert(hn->l); assert(hn->r);
  BIOwrite(b,1, 0);
  printf("!! < encodeTree\n");
  encodeTree(b, hn->l);
  printf("!! > encodeTree\n");
  return encodeTree(b, hn->r);
}

// decode a huffman tree from b into ht
static HN* decodeTree(BIO* b, HT* ht) {
  assert(ht->used < HTREE_SZ);
  HN* n = &ht->n[ht->used]; ht->used += 1;
  int bit = BIOread1(b);
  if(bit < 0) { ht->invalid = true; return NULL; }
  printf("!!   decodeTree bp=%p used=%i ", b->bp, b->used);
  if(bit) {
    *n = (HN) { .v = BIOread8(b) };
    printf("v=0x%X '%c' bp=%p used=%i\n", n->v, n->v, b->bp, b->used);
  } else {
    printf("<<<\n");
    HN* l = decodeTree(b, ht);
    printf("!!   decodeTree bp=%p used=%i >>>\n", b->bp, b->used);
    HN* r = decodeTree(b, ht);
    *n = (HN) { .v = -1, .l = l, .r = r };
  }
  return n;
}

// initalize the HB[256] array
static void HB_init(HB* hbs, HN* n) {
  if(n->v >= 0) {
    assert(n->v < 256); hbs[n->v] = n->hb;
  } else {
    assert(n->l); assert(n->r);
    HB_init(hbs, n->l); HB_init(hbs, n->r);
  }
}

static int l_fmtHT(LS* L) { // (x) -> (string)
  X* x = L_asX(L, 1);
  ALLOC_FIELD(*x, txt, 0x4000);
  uint8_t *s = x->txt; HN_fmt(&s, s + x->txtsz, x->ht.root);
  lua_pushlstring(L, x->txt, s - x->txt);
  return 1;
}

static void HT_finish(X* x) {
  printf("!! calcbits\n");
  HT_calcbits(x->ht.root, 0, 0);
  memset(x->hbs, 0, 256 * sizeof(HB));
  printf("!! HB_init\n");
  HB_init(x->hbs, x->ht.root);
  printf("!! l_htree AFTER:\n");
  HN_printdfs(x->ht.root);
}

static int l_calcHT(LS* L) { // (x, txt) -> ok
  printf("!! l_calcHT\n");
  X* x = L_asX(L, 1);
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 2, &tlen);
  ASSERT(tlen, "empty string (htree calc)");
  htree(&x->ht, txt, txt + tlen);
  if(!x->ht.invalid) HT_finish(x);
  lua_pushboolean(L, !x->ht.invalid);
  return 1;
}

static int l_decodeHT(LS* L) { // (x, txt) -> treelen?, error?
  printf("!! l_decodeHT\n");
  X* x = L_asX(L, 1);
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 2, &tlen);
  ASSERT(tlen, "empty string (htree read)");
  HT* ht = &x->ht; *ht = (HT){0};
  BIO io = (BIO) {.bp=txt, .be=txt+tlen};
  ht->root = decodeTree(&io, &x->ht);
  if(!ht->root) { lua_pushnil(L); lua_pushstring(L, "unknown error"); return 2; }
  HT_finish(x);
  printf("!! l_decodeHT: bp - txt=%i io.used=%i\n", io.bp - txt, io.used);
  printf("!!   [bp]=x%X'%c' '%c' '%c' '%c'\n",
        io.bp[-1], io.bp[-1], io.bp[0], io.bp[1], io.bp[2]);
  lua_pushinteger(L, io.bp - txt + (io.used ? 1 : 0));
  return 1;
}

static int l_encodeHT(LS* L) { // (x) -> (enctree?, error?)
  printf("!! l_encodeHT\n");
  X* x = L_asX(L, 1);
  HT* ht = &x->ht; ASSERT(ht->root, "no tree");
  uint8_t buf[HTREE_SZ]; memset(buf, 0, HTREE_SZ);
  BIO io = (BIO) {.bp = buf, .be = buf+HTREE_SZ};
  int res = encodeTree(&io, x->ht.root);
  if(res) {
    lua_pushnil(L); lua_pushstring(L, "unknown error"); return 2;
  }
  lua_pushlstring(L, buf, io.bp - buf + (io.used ? 1 : 0));
  return 1;
}

// Encode txt using huffman encoding.
// (txt, X) -> encoded?, error
static int l_hencode(LS* L) {
  printf("!! l_hencode\n");
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 1, &tlen);
  X* x = L_asX(L, 2);
  ALLOC_FIELD(*x, dec, tlen + 6); memset(x->dec, 0, tlen + 6);
  BIO io = { .bp = x->dec, .be = x->dec + tlen };
  encv(&io.bp, io.be, tlen); // encode the final length

  uint8_t *tp = txt, *te = txt+tlen;
  HB* hbs = x->hbs;
  while(tp < te) {
    HB hb = hbs[*tp];
    if(!hb.nbits) {
      lua_pushnil(L);
      lua_pushfstring(L, "unknown huffman code: %I", *tp);
      return 2;
    }
    BIOwrite(&io, hb.nbits, hb.bits);
    tp += 1;
  }
  if(io.used) io.bp += 1;
  lua_pushlstring(L, x->dec, io.bp - x->dec);
  return 1;
}

static int HN_read1(HN* n, BIO* io) {
  while(n->v < 0) {
    if(BIOread1(io)) {
      n = n->r;
    } else {
      n = n->l;
    }
  }
  return n->v;
}

// Encode txt using huffman encoding.
// (enc, X) -> txt, error?
static int l_hdecode(LS* L) {
  printf("!! l_hdecode\n");
  size_t elen; uint8_t* enc = (uint8_t*)luaL_checklstring(L, 1, &elen);
  X* x = L_asX(L, 2); HN* root = x->ht.root;
  BIO io = { .bp = enc, .be = enc + elen};
  size_t dlen = decv(&io.bp, io.be, 0,0);
  printf("!! l_hdecode elen=%i dlen=%i\n", elen, dlen);
  ALLOC_FIELD(*x, dec, dlen); uint8_t *dp = x->dec, *de = x->dec + dlen;
  uint8_t* error = NULL;
  while(dp < de) {
    if(io.bp >= io.be) { error = "encoded length too short"; break; }
    *dp = HN_read1(root, &io); dp += 1;
  }
  lua_pushlstring(L, x->dec, dlen);
  if(error) lua_pushstring(L, error); else lua_pushnil(L);
  printf("!! l_hdecode out root=%p\n", x->ht.root);
  return 2;
}

//************************
//* 3.a Lua Bindings (and run test)

// int -> str: encode integer using encv
static int l_encv(LS* L) {
  uint8_t buf[8]; uint8_t* b = buf; encv(&b, buf+8, luaL_checkinteger(L, 1));
  lua_pushlstring(L, buf, b-buf);
  return 1;
}

// str -> int, elen: decode integer using decv
// returns: the integer and the number of bytes used to encode it.
static int l_decv(LS* L) {
  printf("!! l_decv\n");
  size_t tlen; uint8_t* txt = (uint8_t*)luaL_checklstring(L, 1, &tlen);
  uint8_t* tp = txt; lua_pushinteger(L, decv(&tp, txt+tlen, 0, 0));
  lua_pushinteger(L, tp - txt);
  return 2;
}

static const struct luaL_Reg smol_sys[] = {
  {"createX", l_createX},
  {"rpatch", l_rpatch}, {"rdelta", l_rdelta},
  {"rcmdlen", l_rcmdlen},
  {"fmtHT", l_fmtHT},       {"calcHT", l_calcHT},
  {"decodeHT", l_decodeHT}, {"encodeHT", l_encodeHT},
  {"hencode", l_hencode}, {"hdecode", l_hdecode},
  {"encv", l_encv}, {"decv", l_decv},
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


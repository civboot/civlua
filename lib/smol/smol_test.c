#include "smol.c"

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

static void test_encode_v() {
  printf("# test_decv (c)\n");
  size_t i = 0;
  uint8_t b[12] = "\x85\x0F\x33";
  uint8_t *bp = b, *be = b + 12;
  uint64_t v = 0; assert(decv(&bp,be, &v,0) >= 0);
  assert((bp - b) == 2);
  assert(v == ((0x0F << 7) | (0x5)));

 #define T_ROUND(V, IEXPECT) \
  bp = b; assert(0   == encv(&bp, be, V));  assert(IEXPECT == bp-b); \
  bp = b; v = 0; assert(0 == decv(&bp,be, &v,0)); \
    assert((V) == v); assert(bp-b==IEXPECT);
  T_ROUND(0x00,  1);
  T_ROUND(0x01,  1); T_ROUND(0x37,  1); T_ROUND(0x07F,  1);
  T_ROUND(0x080, 2); T_ROUND(0x100, 2); T_ROUND(0x3FFF, 2);
  T_ROUND(0x4000, 3);
  T_ROUND(0x7FFFFFFF, 5);
#undef T_ROUND
}

static void test_encode_cmds() {
  printf("# test_encode_cmds (c)\n");
  uint64_t len, v;
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
  T_ROUND(CPY, 7,    2, 1, 5);
    v = 0; assert(0 == decv(&x.xp,x.xe, &v,0)); assert(v == 5);
  T_ROUND(CPY, 7,    4, 1, 0x4000);
    v = 0; assert(0 == decv(&x.xp,x.xe, &v,0)); assert(0x4000 == v);
#undef T_ROUND
}

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

void test_BIO() {
  printf("# test_BIO (c)\n");
  uint8_t dat[256] = {0x57, 0x53, 0}; // 0101 0111  0101 0011
  BIO io = {.bp = dat, .be=dat+255};
  assert(0 == BIOread1(&io)); assert(1 == BIOread1(&io));
  assert(0 == BIOread1(&io)); assert(1 == BIOread1(&io));
  assert(4 == io.used); assert(dat == io.bp);
  assert(0x75 == BIOread8(&io));
  assert(0x30 == BIOread8(&io));
  assert(4 == io.used);

  // write the same as above
  io.used = 0; io.bp = dat; memset(dat, 0, 256);
  BIOwrite(&io,1, 0); BIOwrite(&io,1, 1); assert(0x40 == *dat); // 0100 0000
  BIOwrite(&io,1, 0); BIOwrite(&io,1, 1); assert(0x50 == *dat); // 0101 0000
  BIOwrite(&io,8, 0x75);   // [0]:0101.0111  [1]: 0101.0000
  assert(0x57 == dat[0]); assert(0x50 == dat[1]);
  BIOwrite(&io,1, 0); BIOwrite(&io,1, 0); BIOwrite(&io,1, 1); BIOwrite(&io,1, 1);
  assert(0x53 == dat[1]);
  assert(8 == io.used);

  // test a few more edge cases
  BIOwrite(&io,1, 1); assert(0x53 == dat[1]); assert(0x80 == dat[2]);
  assert(1 == io.used);
  io.used = 8; BIOwrite(&io,8, 0xFE);
  assert(0x80 == dat[2]); assert(0xFE == dat[3]);

  // now test the HT_tree use-case below
  io.used = 0; io.bp = dat; memset(dat, 0, 256);
  BIOwrite(&io,1, 0); BIOwrite(&io,1, 0); BIOwrite(&io,1, 1);
  assert(0x20 == dat[0]); assert(3 == io.used);

  BIOwrite(&io,8, 0x3B); // ';' (0011 1011) -> 0010.0111  011-.---
  assert(0x27 == dat[0]); assert(0x60 == dat[1]);
  BIOwrite(&io,1, 1); assert(0x70 == dat[1]);

  io.used = 0; io.bp = dat;
  assert(0 == BIOread1(&io)); assert(0 == BIOread1(&io));
  assert(1 == BIOread1(&io)); assert(3 == io.used);
  assert(0x3B == BIOread8(&io));
  assert(1 == BIOread1(&io));

  // now test the first hencode test case in test.lua
  io.used = 0; io.bp = dat; memset(dat, 0, 256);
  BIOwrite(&io,2, 2); BIOwrite(&io,2, 2); // 'AA'
  BIOwrite(&io,2, 2); BIOwrite(&io,2, 2); // 'AA'
  assert(8 == io.used); assert(dat == io.bp);
  assert(0xAA == io.bp[0]);

  BIOwrite(&io,2, 1); BIOwrite(&io,2, 1); // '  ' 0101=5
  BIOwrite(&io,2, 1); BIOwrite(&io,2, 3); // ' z' 0111=7
  assert(8 == io.used); assert(dat+1 == io.bp);
  assert(0x57 == dat[1]);

  // now test "abcdefg" test case in test.lua
  io.used = 0; io.bp = dat; memset(dat, 0, 256);
  BIOwrite(&io,3, 0x4);                         // 100 -> 100. ....
  BIOwrite(&io,3, 0x3); assert(dat[0] == 0x8C); // 011 -> 1000 11..
  BIOwrite(&io,3, 0x7); assert(dat[0] == 0x8F); // 111 -> 1000 1111  1... ....
  BIOwrite(&io,2, 0x0); assert(dat[1] == 0x80); //  00 -> 1000 1111  100. ....

// !! HN_read1 out: 0x61 'a'                       
// !!   HN_read1(0:left)
// !!   HN_read1(1:right)
// !!   HN_read1(1:right)
// !! HN_read1 out: 0x62 'b'
// !!   HN_read1(0:left)
// !!   HN_read1(0:left)
// !! HN_read1 out: 0x64 'd'
// !!   HN_read1(1:right)
// !!   HN_read1(0:left)
// !!   HN_read1(0:left)

}

static void test_Heap() {
  HT ht; Heap h;
  uint8_t* dat = "AAAA   zzzz;;";
  hheap(&ht, &h, dat, dat+strlen(dat));
  assert(ht.n['A'].count == 4); assert(ht.n['A'].v == 'A');
  assert(ht.n[' '].count == 3);
  assert(h.len == 4);
  assert(h.a[0] == &ht.n[';']); // smallest
  assert(HT_heappop(&ht, &h) == &ht.n[';']);
  assert(h.a[0] == &ht.n[' ']); assert(h.len == 3);
  HT_heappush(&ht, &h, &ht.n[';']);
  assert(h.a[0] == &ht.n[';']); assert(h.len == 4);
}

static bool HN_equal(HN* n, HN* o) {
  if((n == NULL) || (o == NULL)) return n == o;
  return (n->v == o->v)
      && HN_equal(n->l, o->l)
      && HN_equal(n->r, o->r);
}

#define ASSERT_COUNT(N, C) if(count) assert((N)->count == C);
void expectTree(HN* root, bool count) {
  // Note: this is a possible correct representation
  HN* l = root->l; ASSERT_COUNT(l, 5); assert(l->v == -1);
    assert(l->l->v == ';'); ASSERT_COUNT(l->l, 2);
    assert(l->r->v == ' '); ASSERT_COUNT(l->r, 3);
  HN* r = root->r; ASSERT_COUNT(r, 8); assert(r->v == -1);
    assert(r->l->v == 'A'); ASSERT_COUNT(r->l, 4);
    assert(r->r->v == 'z'); ASSERT_COUNT(r->r, 4);
}

static void test_HT() {
  printf("# test_HT (c)\n");
  uint8_t* dat = "AAAA   zzzz;;";
  HT ht; htree(&ht, dat, dat + strlen(dat));
  assert(ht.root->count == strlen(dat)); assert(ht.root->v == -1);
  expectTree(ht.root, true);

  uint8_t buf[256]; memset(buf, 0, 256);
  BIO io = { .bp = buf, .be = buf+256 };

  // write tree
  assert(!encodeTree(&io, ht.root));
  assert(io.bp - buf == 4); assert(io.used == 7);

  // read tree
  io.bp = buf; io.used = 0; // reset
  HT ht2 = {0};
  ht2.root = decodeTree(&io, &ht2); assert(ht2.root);
  expectTree(ht2.root, false);
  assert(HN_equal(ht.root, ht2.root));

  // finish initialization
  HT_calcbits(ht.root, 0,0);
  printf("!! ht 'A' bits=%i\n", ht.n['A'].hb.bits);
  HB hbs[256];
  memset(hbs, 0, 256 * sizeof(HB)); HB_init(hbs, ht.root);
  assert(0 == hbs[0].bits); assert(0 == hbs[255].bits);
  printf("!! %i\n", hbs['A'].nbits);

  assert(2 == hbs[';'].nbits); assert(0 == hbs[';'].bits);
  assert(2 == hbs[' '].nbits); assert(1 == hbs[' '].bits);
  assert(2 == hbs['A'].nbits); assert(2 == hbs['A'].bits);
  assert(2 == hbs['A'].nbits); assert(3 == hbs['z'].bits);
}

int main() {
  printf("# TEST smol.c\n");
  test_po2();
  test_encode_v();
  test_encode_cmds();
  test_fp();
  test_window();
  test_BIO();
  test_Heap();
  test_HT();
  return 0;
}

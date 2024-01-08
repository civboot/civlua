# This is patience diff implemented in python for reference.
#
# Thanks to https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/
#
# Tests taken from that article

from dataclasses import dataclass
from pprint import pprint as pp

@dataclass
class Count:
  i: int = 0; count: int = 1
  nxt: 'Count' = None # used for patience sort


def linesUniqueCountMaps(linesA, linesB, a, a2, b, b2):
  """Return MapA[line, CountA] and MapB[line, CountB].

  countB contains only items which are unique (count==1) from countA
  and which were added in increasing order from A.

  This is so that we only output unique AND increasing matching indexes.
  For example
      A    B
     --------
      1    3    /- therefore 3 can't match
      2 \- 1  1 matches with 1
      3    4

  Diff result:
      A    B
     --------
    +      3
      1    1
    - 2
    - 3
    +      4

  Note: Only count == 1 from countB should be used in the patience stacks.
  """
  countA = {}
  for a in range(a, a2+1):
    line = linesA[a]
    c = countA.get(line)
    if not c:
      c = Count()
      countA[line] = c
    c.i = a; c.count += 1
  countB = {}

  a = -1
  for b in range(b, b2+1):
    line = linesB[b]
    cA = countA.get(line)
    if cA and cA.count == 1 and a < cA.i:
      cB = countB.get(line)
      if not cB:
        c = Count()
        countB[line] = c
      cB.i = b; eB.count += 1
      a = cA.i
  return countA, countB

def patienceStacks(countMap):
  """Return the patience stacks from countMap.

  Patience stacks are a set of stacks sorted using line indexes of unique lines.

  The algorithm is akin to playing a simplistic game of "patience" (aka
  solitare) where the top of each stack has a smaller value than the item below
  it or it's added to the next stack.

  This allows us to get the Longest Increasing Subsequence with patienceLIS.
  """
  stacks = []
  for c in countMap.values():
    for si, s in enumerate(stacks):
      top = s[-1]
      print('c < top', c.i, top.i)
      if c.i < top.i:
        if si != 0:
          # set nxt to top of prev stack
          # (unless this is si==0, the first stack)
          c.nxt = stacks[si-1][-1]
        s.append(c)
        break
    else:
      if not stacks: stacks.append([c])
      else:
        # no stack found, create one and set nxt
        # to prev stack top
        c.nxt = stacks[-1][-1]
        stacks.append([c])
  return stacks

def patienceLIS(stacks):
  """Return the Longest Increasing Subsequence of count.i
  from the patienceStacks.

  countMap should come from linesUniqueCountMaps.
  """
  return [s[-1].i for s in stacks]

def skipEqLinesTop(linesA, linesB, a, a2, b, b2):
  """Walk lines at the top (index=0), skipping equal lines.

  Items i<a and i<b are equal to eachother (or vice-versa if inc==-1).
  """
  while a <= a2 and b <= b2:
    if linesA[a] != linesB[b]:
      return a, b
    a += 1; b += 1
  return a, b

def skipEqLinesBot(linesA, linesB, a, a2, b, b2):
  """Walk lines at the bot (index=-1) skipping equal lines.

  Items i>a2 and i>b2 are equal to eachother
  """
  while a <= a2 and b <= b2:
    if linesA[a2-1] != linesB[b2-1]:
      return a2, b2
    a2 -= 1; b2 -= 1
  return a2, b2

def patienceDiffI(out, linesA, linesB, a, a2, b, b2):
  """Get the patience dif indexes (a/b indexes inclusive).
  """
  b_, b2_ = b, b2 # cache absolute (starting) min/max of b
  a, b   = skipEqLinesTop(linesA, linesB, a, a2, b, b2)
  a2, b2 = skipEqLinesBot(linesA, linesB, a, a2, b, b2)

  # B unchanged lines (top)
  out.extend([(' ', i) for i in range(b_, b)])

  # find changed lines
  countMapA, countMapB = linesUniqueCountMaps(linesA, linesB, a, a2, b, b2)
  stacksB = patienceStacks(countMapB)
  lisB = patienceLIS(stacksB)

  # divide and conquere: split by changed lines and recurse
  # into a sub-patience diff.
  # i is the lower bound and b the moving upper bound.
  i = 0
  a_, a2_ = a, a2 # cache absolute (pre divide) min/max of a
  while i < len(lisB):
    # bsi=bSplitIndex, we know we have equal lines here
    bsi = lisB[i]
    line = linesB[bsi]; a = countMapA[line].i
    # bSplitIndex2 is at either next split index or the end of b
    bsi2 = lisB.get(i+1) or b2
    line2 = linesB.get(bsi2)
    if line2:          a2 = countMapA[line2].i
    else:              a2 = a2_
    assert a <= a2; assert b <= b2
    out.append((' ', line))
    patienceDiff(out, linesA, linesB, a+1, a2-1, i+1, b-1)
    b = bsi + 1
    i = i
  if not lisB:
    out.extend([('+', i) for i in range(b, b2)])
    out.extend([('-', i) for i in range(a, a2)])
  assert b <= b2

  # B unchanged lines (top)
  out.extend([(' ', i) for i in range(b2, b2_+1)])
  return out

def patienceDiff(linesA, linesB):
  indexes = []
  patienceDiffI(indexes, linesA, linesB, 0, len(linesA)-1, 0, len(linesB)-1)
  diff = []
  pp(indexes)
  for kind, i in indexes:
    if   kind == ' ': diff.append((' ', linesB[i]))
    elif kind == '-': diff.append(('-', linesA[i]))
    elif kind == '+': diff.append(('+', linesB[i]))
    else: assert False, (kind, i)
  return diff

def mockCounts(indexes):
  return {e: Count(i) for e, i in enumerate(indexes)}

def stackIs(stacks):
  out = []
  for s in stacks:
    out.append([c.i for c in s])
  return out

def testPatienceStacks():
  counts = mockCounts([5, 3, 1, 8, 2, 4, 5])
  expected = [
    [5, 3, 1, ],
    [8, 2, ],
    [4, ],
    [5, ],
  ]
  stacks = patienceStacks(counts)
  result = stackIs(stacks)
  assert(expected == result)

  expected = [1, 2, 4, 5]
  result = patienceLIS(stacks)
  assert(expected == result)

def testGetEqLines():
  linesA = 'this is incorrect and so is this'.split()
  linesB = 'this is good and correct and so is this'.split()
  a, a2, b, b2 = 0, len(linesA), 0, len(linesB)
  assert (7, 9)  == (a2, b2)
  a, b = skipEqLinesTop(linesA, linesB, a, a2, b, b2)
  assert 2 == a;  assert 2 == b

  a2, b2 = skipEqLinesBot(linesA, linesB, a, a2, b, b2)
  assert 3 == a2; assert 5 == b2


def testPatienceDiff():
  linesA = 'this is incorrect and so is this'.split()
  linesB = 'this is good and correct and so is this'.split()
  expected = [
      (' ', 'this'), (' ', 'is'),
      ('+', 'good'), ('+', 'and'), ('+', 'correct'),
      ('-', 'incorrect'),
      (' ', 'and'), (' ', 'so'), (' ', 'is'), (' ', 'this'),
  ]
  result = patienceDiff(linesA, linesB)
  print('## Expected:')
  pp(expected)
  print('## Result:')
  pp(result)
  assert expected == result


if __name__ == '__main__':
  testPatienceStacks()
  testGetEqLines()
  testPatienceDiff()


-- Bash equivalent:   cat input.txt  |    grep foo  >> output.txt
local grep = Piper | open'input.txt' | Sh'grep foo' >> 'output.txt'
assert(grep.rc == 0)

Piper = mt.record'Pipe'
  :field('scheduled', 'number')
  :field('done',      'number')
  :fieldMaybe'prev'
getmetatable(Piper).__call = function(ty_, prev)
  return mt.new({scheduled=0, done=0})
end
getmetatable(Piper).__bor = getmetatable(Pipe).__call

Piper.__bor = function(p, nxt)
  assert(rawget(getmetatable(nxt), '__bor'), "next item not pipeable")
  push(p, nxt)
  local prev = p.prev
  if not prev then p.prev = nxt; return end
  p.scheduled = p.scheduled + 1
  lap.schedule(function()
    rawget(getmetatable(prev), '__bor')(prev, nxt)
    p.done = p.done + 1
  end)
  p.prev = nxt
  return p
end

Piper.__call = function(p, sleep)
  sleep = sleep or p.SLEEP
  while p.done < p.scheduled do yield('sleep', sleep) end
  p.prev = nil
  return p.prev
end

Piper.__shr = function(p, path)
  local prev = p() -- finish pipe
  rawget(getmetatable(prev), '__bor')(prev, open(path, 'w'))
  return prev
end

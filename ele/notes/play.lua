require'civ':grequire()
grequire'shix'

grequire'plterm'

print('Play')


outf('writing ', 'stuff')

saved, err, msg = savemode()
assert(err, msg)
atexit = {__gc = function()
  print('\nexiting\n')
  restoremode(saved)
  print('\nmode restored\n')
end}
setmetatable(atexit, atexit)

setrawmode()

outf('clearing')
sleep(0.5)
clear()

GRID_ROW = [[
1 2 3 4 5 6 7 9 0     1 2 3 4 5 6 7 9 0     1 2 3 4 5 6 7 8 9]]

function grid(start, end_, col)
  for i=start,end_ do
    golc(i, col); cleareol()
    outf(GRID_ROW)
  end
end

lines, cols = dimensions()

function doing(msg)
  golc(lines, 8); cleareol(); outf(msg)
end
golc(lines, 0)
outf('DOING: ')

doing('grid 1 5 0')
grid(1, 5, 0)
sleep(2)

doing('grid 8 12 5')
grid(8, 12, 5)
sleep(2)

restoremode(saved)

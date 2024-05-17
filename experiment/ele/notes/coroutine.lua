require'civ':grequire()
grequire'shix'

yld = coroutine.yield
resume = coroutine.resume
create = coroutine.create

co = create(function()
  for i=1,10 do
    print('co', i)
    yld()
  end
end)

print('running co routine')
sleep(0.1); resume(co)
sleep(0.1); resume(co)
sleep(0.1); resume(co)

co = create(function() return 42 end)
a, b = resume(co)
assert(a); assert(42 == b)
assert(not resume(co))

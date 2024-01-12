
import re
import os
path = os.path

def readpath(path):
  with open(path) as f: return f.read()

def writepath(path, text):
  with open(path, 'w') as f: f.write(text)

exp = re.compile(r"^.*'metaty.*$")
def repl(m):
  print('  ?? replacing', m)
  return "local pkg = require'pkg'\n" + m.group(0)

for base, _dirs, fnames in os.walk('./'):
  for fname in fnames:
    fpath = path.join(base, fname)
    if not fpath.endswith('.lua'): continue
    text = readpath(fpath)
    if "require'pkg'" in text: continue
    print('Updating', fpath)
    res = exp.sub(repl, text)
    if res == text:
      print('  ! No difference')
    else:
      writepath(fpath, res)

print('Done')

DELETED_LABEL='(deleted)	1969-12-31 17:00:00.000000000 -0700'

D=$PWD
TD=$PWD/cmd/pvc/testdata
OD=$PWD/.out/pvc

function create1() {
  echo create1
  echo "cd $TD"; cd $TD
  echo ls;       ls
  echo creating 1
  diff -N --unified=1 DNE story.txt.1 --label=story.txt --label=story.txt \
    > patch.story.txt.1
  diff -N --unified=1 DNE hello.lua.1 --label=hello.lua --label=hello.lua \
    > patch.hello.lua.1
  cat patch.story.txt.1 patch.hello.lua.1 > patch.1
}

function create2() {
  cd $TD
  # creating 2 (with deleted hello.lua)
  diff -N --unified=1 story.txt.1 story.txt.2 --label=story.txt --label=story.txt \
    > patch.story.txt.2
  diff -N --unified=1 hello.lua.1 DNE  --label=hello.lua  \
    --label="$DELETED_LABEL" > patch.hello.lua.2
  cat patch.story.txt.2 patch.hello.lua.2 > patch.2
}

function efile() { echo "## $1"; cat "$1"; }

function patch1() {
  rm -rf $OD; mkdir $OD; cd $OD
  cat $TD/patch.1 | patch -u
  efile $OD/story.txt
  efile $OD/hello.lua
}

function patch2() {
  cat $TD/patch.2 | patch -u
  efile $OD/story.txt
  efile $OD/hello.lua
}

echo "Running $1"
$1

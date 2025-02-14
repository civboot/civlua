# This file is for playing with the unix diff/patch tools and testing
# how they interact.
DNE=.pvc/DNE

D=$PWD
TD=$PWD/cmd/pvc/testdata
OD=$PWD/.out/pvc

# Create patch.1 from story.txt and hello.lua
function create1() {
  echo create1
  echo "cd $TD"; cd $TD
  echo ls;       ls
  echo creating 1
  # create comes FROM /dev/null and to the path
  diff -N --unified=1 /dev/null story.txt.1 --label=/dev/null --label=story.txt \
    > patch.story.txt.1
  diff -N --unified=1 /dev/null hello.lua.1 --label=/dev/null --label=hello.lua \
    > patch.hello.lua.1
  cat patch.story.txt.1 patch.hello.lua.1 > patch.1
}

# Create patch.2 from story.txt and delete hello.lua
function create2() {
  cd $TD
  # creating 2 (with deleted hello.lua)
  diff -N --unified=1 story.txt.1 story.txt.2 --label=story.txt --label=story.txt \
    > patch.story.txt.2
  # delete goes TO /dev/null
  diff -N --unified=1 hello.lua.1 /dev/null  --label=hello.lua  --label=/dev/null \
    > patch.hello.lua.2
  cat patch.story.txt.2 patch.hello.lua.2 > patch.2
}

function efile() { echo; echo "## efile: $1"; cat "$1"; }

# apply patch.1
function patch1() {
  rm -rf $OD; mkdir $OD; cd $OD
  cat $TD/patch.1 | patch -Nu
  efile $OD/story.txt
  efile $OD/hello.lua
}

# apply patch.2
function patch2() {
  cd $OD
  cat $TD/patch.2 | patch -Nu
  efile $OD/story.txt
  efile $OD/hello.lua
}

# Reverse patch.2 getting 1 back
function patch2_1() {
  cd $OD
  cat $TD/patch.2 | patch -Ru
  efile $OD/story.txt
  efile $OD/hello.lua
}

echo "Running $1"
$1

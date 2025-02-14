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
  diff -N --unified=0 /dev/null story.txt.1 --label=/dev/null --label=story.txt \
    > patch.story.txt.1
  diff -N --unified=0 /dev/null hello.lua.1 --label=/dev/null --label=hello.lua \
    > patch.hello.lua.1
  cat patch.story.txt.1 patch.hello.lua.1 > patch.1
}

# Create patch.2 from story.txt and delete hello.lua
function create2() {
  cd $TD
  # creating 2 (with deleted hello.lua)
  diff -N --unified=0 story.txt.1 story.txt.2 --label=story.txt --label=story.txt \
    > patch.story.txt.2
  # delete goes TO /dev/null
  diff -N --unified=0 hello.lua.1 /dev/null  --label=hello.lua  --label=/dev/null \
    > patch.hello.lua.2
  cat patch.story.txt.2 patch.hello.lua.2 > patch.2
}

# Create 3 and 3b. 3 represents a "main" change whereas 3b must be rebased
function create3() {
  cd $TD
  # creating 2 (with deleted hello.lua)
  diff -N --unified=0 story.txt.2 story.txt.3 --label=story.txt --label=story.txt \
    > patch.3
  diff -N --unified=0 story.txt.2 story.txt.3b --label=story.txt --label=story.txt \
    > patch.3b
}

# renames story.txt -> kitty.txt and applies small diff
function create4() {
  cd $TD
  diff -N --unified=0 story.txt.3final story.txt.4 --label=story.txt --label=kitty.txt \
    > patch.4
}

function efile() { echo; echo "## efile: $1"; cat "$1"; }

# apply patch.1
function patch1() {
  rm -rf $OD; mkdir $OD; cd $OD
  patch -Nu --input=$TD/patch.1
  efile $OD/story.txt
  efile $OD/hello.lua
}

# apply patch.2
function patch2() {
  cd $OD
  patch -Nfu --input=$TD/patch.2; echo "rc=$?"
  efile $OD/story.txt
  efile $OD/hello.lua
}

# Reverse patch.2 getting 1 back
function patch2_1() {
  cd $OD; patch -Rfu --input=$TD/patch.2
  efile story.txt
  efile hello.lua
}

function patch3 {
  cd $OD; patch -Nfu --input=$TD/patch.3; echo "rc=$?"
  efile story.txt
}

function patch3b {
  cd $OD; patch -Nfu --input=$TD/patch.3b; echo "rc=$?"
  efile story.txt
}

# use merge instead of patch when rebasing / cherry picking
function rebase3 {
  cd $OD
  merge story.txt $TD/story.txt.2 $TD/story.txt.3b
  efile story.txt
}

# should happen after rebase3b
function patch4 {
  cd $OD; patch -Nfu --input=$TD/patch.4; echo "rc=$?"
  efile story.txt
  efile kitty.txt
}

echo "Running $1"
$1

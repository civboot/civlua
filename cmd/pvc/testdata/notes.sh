CREATED_LABEL='(created)	1969-12-31 17:00:00.000000000 -0700'
DELETED_LABEL='(deleted)	1969-12-31 17:00:00.000000000 -0700'

D=$PWD
TD=$PWD/cmd/pvc/testdata
OD=$PWD/.out/pvc

function create1() {
  cd $TD
  # creating 1
  diff -N --unified=1 DNE story.txt.1 --label="$CREATED_LABEL" --label=story.txt \
    > patch.story.1
  diff -N --unified=1 DNE hello.lua.1 --label="$CREATED_LABEL" --label=hello.lua \
    > patch.hello.1
  cat patch.story.txt.1 patch.hello.lua.1 > patch.1
}

function create2() {
  cd $TD
  # creating 2 (with deleted hello.lua)
  diff -N --unified=1 story.1 story.2 --label=story.txt --label=story.txt \
    > patch.story.2 
  diff -N --unified=1 hello.1 DNE  --label=hello.lua  \
    --label=$DELETED_LABEL > patch.hello.2
  cat patch.story.2 patch.hello.2 > patch.2
}

function patch1() {
  rm -rf $OD; mkdir $OD; cd $OD
  cat $TD/patch.1 | patch -u
}

function patch2() {
  cat $TD/patch.2 | patch -u
}

$1

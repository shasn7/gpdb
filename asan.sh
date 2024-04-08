#!/usr/bin/env bash

sourced() {
GPHOME=`cat "./GPHOME"`

if ! [ -d "./gpAux/gpdemo" ]; then
    echo "Script is not in GPDB source directory!"
    exit 1
fi

export DATADIRS=`realpath "./gpAux/gpdemo/datadirs"`
export MASTER_DATA_DIRECTORY="$DATADIRS/qddir/demoDataDir-1"
export PGPORT="6000"

if ! [ -d "$GPHOME" ]; then
    echo "\$GPHOME ($GPHOME) does not exist!"
else
    . "$GPHOME/greenplum_path.sh"
fi
}

executed() {
# Figure out the GPHOME and PREFIX.
if [ "$GPHOME" != "" ]; then
    PREFIX="$GPHOME"
elif [ -f "./GPHOME" ]; then
    PREFIX=`cat "./GPHOME"`
else
    echo -n "\$GPHOME was not found. PREFIX="
    read PREFIX
fi

if ! [ -d "$PREFIX" ]; then
    echo "PREFIX ($PREFIX) does not exist!"
    exit 1
fi

# Save the PREFIX into a file and ignore the file.
if ! [ -f "./GPHOME" -a -d "./.git/info/" ]; then
    echo "GPHOME" >> "./.git/info/exclude"
fi

echo `realpath "$PREFIX"` > "./GPHOME"

CC="gcc"
CXX="g++"
LD="gold"

COMMON_CFLAGS="\
-O0 \
-g3 \
-fuse-ld=$LD"

ASAN_CFLAGS="\
-fsanitize=address \
-fsanitize=undefined \
-fsanitize-recover=address \
-fno-omit-frame-pointer \
-fPIC \
-Wl,--no-as-needed"

ERROR_CFLAGS="\
-Wno-error=uninitialized \
-Wno-error=maybe-uninitialized \
-Wno-error=deprecated-copy \
-Wno-error=nonnull-compare \
-Wno-error=implicit-function-declaration"

LDFLAGS="\
-fsanitize=address \
-fsanitize-recover=address \
-fPIE \
-ldl \
-lasan \
-Wl,--no-as-needed"

DEBUG_DEFS="\
-DEXTRA_DYNAMIC_MEMORY_DEBUG \
-DCDB_MOTION_DEBUG"

echo -n "PREFIX='$PREFIX'. Enter to continue. "
read _

set +xe

export CFLAGS="\
$DEBUG_DEFS \
$COMMON_CFLAGS \
-O0 \
$ASAN_CFLAGS \
$ERROR_CFLAGS \
$LDFLAGS"

export AUTOCONF_FLAGS="\
--with-python \
--with-pythonsrc-ext \
--enable-depend \
--with-libxml \
--enable-debug-extensions \
--enable-cassert"

./configure $AUTOCONF_FLAGS --prefix="$PREFIX"
}

if [ "$0" != "$BASH_SOURCE" ]; then
    sourced
else
    executed
fi

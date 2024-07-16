#!/usr/bin/env bash

set -e

# Variables to be modified manually. A note on this is in README.md.
CC=""
CXX=""
LD=""
ASAN_LOG_PATH=""

# Globals which shouldn't be modified.
CLANG=0
ASAN_SO=""
ASAN_SO_PATH=""
SHARED_LIBASAN=""

case "$CC" in clang*)
    CLANG=1
esac

sourced() {
GPSRC=`realpath $(dirname $BASH_SOURCE)`
GPHOME=`cat "$GPSRC/GPHOME"`

export DATADIRS="$GPSRC/gpAux/gpdemo/datadirs"
export MASTER_DATA_DIRECTORY="$DATADIRS/qddir/demoDataDir-1"
export PGPORT="6000"

if ! [ -d "$GPHOME" ]; then
    echo "WARNING: \$GPHOME ($GPHOME) does not exist, can't source greenplum_path.sh."
    return 1
fi

. "$GPHOME/greenplum_path.sh"
}

executed() {
# Find out the PREFIX to use.
if [ "$GPHOME" != "" ]; then
    PREFIX="$GPHOME"
elif [ -f "./GPHOME" ]; then
    PREFIX=`cat "./GPHOME"`
else
    echo "WARNING: \$GPHOME was not found."
    echo -n "PREFIX="
    read PREFIX
fi

# ./GPHOME does not exist if the script was run for the first time.
#
# Modify greenplum_path.sh generation script to set ASAN_OPTIONS and LD_PRELOAD.
# gpssh sources greenplum_path.sh every command.
if ! [ -f "./GPHOME" ]; then
    GEN_PATH="./gpMgmt/bin/generate-greenplum-path.sh"

    echo "" >> "$GEN_PATH"
    echo "echo ''" >> "$GEN_PATH"

    _ASAN_OPTIONS="log_path='$ASAN_LOG_PATH':halt_on_error=0"
    echo "echo \"export ASAN_OPTIONS=$_ASAN_OPTIONS\"" >> "$GEN_PATH"

    _LD_PRELOAD="\$LD_PRELOAD:$_ASAN_SO_PATH"
    echo "echo \"export LD_PRELOAD=$_LD_PRELOAD\"" >> "$GEN_PATH"
fi

# Save the GPHOME variable.
echo `realpath "$PREFIX"` > "./GPHOME"

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

echo -n "PREFIX='$PREFIX'. Enter to continue."
read _

set +xe

export CFLAGS="\
$DEBUG_DEFS \
$COMMON_CFLAGS \
$ASAN_CFLAGS \
$SHARED_LIBASAN \
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

main() {
if [ "$CC" == "" -o "$CXX" == "" -o "$LD" == "" -o "$ASAN_LOG_PATH" == "" ]; then
    echo "ERROR: Some of the required variables were not set."
    echo "Please modify this script first before running it!"
    return 1
fi

if [ "$CLANG" == 1 ]; then
    echo "ERROR: Clang is not supported."
    return 1
fi

ASAN_SO="libasan.so"
ASAN_SO_PATH=`realpath $($CC -print-file-name=$ASAN_SO)`

# BASH_SOURCE is empty if the script was executed instead of being sourced.
if [ "$0" != "$BASH_SOURCE" ]; then
    sourced
else
    executed
fi
}

main

#!/usr/bin/env bash

# Variables to be modified manually. A note on this is in README.md.
CC=""
CXX=""
LD=""
ASAN_LOG_PATH=""

# Globals which shouldn't be modified.
ASAN_SO=""
ASAN_SO_PATH=""
SHARED_LIBASAN=""

# Modify greenplum_path.sh generation script to set ASAN_OPTIONS and LD_PRELOAD.
# gpssh sources greenplum_path.sh every command.
setup() {
GEN_PATH="./gpMgmt/bin/generate-greenplum-path.sh"

echo >> "$GEN_PATH"
echo "echo" >> "$GEN_PATH"

CUSTOM_ASAN_OPTIONS="log_path=$ASAN_LOG_PATH:halt_on_error=0"
echo "Please put the following line into your /etc/bash.bashrc:"
echo "echo \"export ASAN_OPTIONS=$CUSTOM_ASAN_OPTIONS\""
echo -n "Enter to continue."
read _

CUSTOM_LD_PRELOAD="\$LD_PRELOAD:$ASAN_SO_PATH"
echo "echo \"export LD_PRELOAD=$CUSTOM_LD_PRELOAD\"" >> "$GEN_PATH"

# Apply patch to avoid hanging.
cat <<EOF | git apply -
diff --git a/gpMgmt/bin/gppylib/commands/base.py b/gpMgmt/bin/gppylib/commands/base.py
index 138ffc679c7..6b73dd69020 100755
--- a/gpMgmt/bin/gppylib/commands/base.py
+++ b/gpMgmt/bin/gppylib/commands/base.py
@@ -448,8 +448,14 @@ class LocalExecutionContext(ExecutionContext):
         for k in keys:
             cmd.cmdStr = "%s=%s && %s" % (k, cmd.propagate_env_map[k], cmd.cmdStr)

+        # ps and pgrep hang due to us screwing with LD_PRELOAD, this is a
+        # hack to avoid glibc locales exploding
+        cmd.cmdStr = cmd.cmdStr.replace("ps -ef", "unset LD_PRELOAD; ps -ef")
+        cmd.cmdStr = cmd.cmdStr.replace("pgrep", "unset LD_PRELOAD; pgrep")
+
         # executable='/bin/bash' is to ensure the shell is bash.  bash isn't the
         # actual command executed, but the shell that command string runs under.
+        print "running local command: '%s'" % cmd.cmdStr
         self.proc = gpsubprocess.Popen(cmd.cmdStr, env=None, shell=True,
                                        executable='/bin/bash',
                                        stdin=subprocess.PIPE,
EOF
}

sourced() {
GPSRC=`realpath $(dirname $BASH_SOURCE)`

if ! [ -f "$GPSRC/GPHOME" ]; then
    echo "GPHOME does not exist. Please run this script before sourcing it."
    return 1
fi

if [ "$ASAN_OPTIONS" == "" ]; then
    echo "ERROR: \$ASAN_OPTIONS is not set! Please delete ./GPHOME and rerun this script."
    return 1
fi

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
if ! [ -f "./GPHOME" ]; then
    setup
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

case "$CC" in clang*)
    echo "ERROR: Clang is not supported."
    return 1
esac

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

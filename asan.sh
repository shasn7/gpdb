#!/usr/bin/env bash

# Variables to be modified manually. A note on this is in README.md.
LD=""
ASAN_LOG_PATH=""

# Globals which shouldn't be modified.
CC="gcc"
CXX="g++"

ASAN_SO=""
ASAN_SO_PATH=""

# Modify greenplum_path.sh generation script to set ASAN_OPTIONS and LD_PRELOAD.
# gpssh sources greenplum_path.sh every command.
setup() {
    GEN_PATH="./gpMgmt/bin/generate-greenplum-path.sh"

    echo >> "$GEN_PATH"
    echo "echo" >> "$GEN_PATH"

    CUSTOM_ASAN_OPTIONS="log_path=$ASAN_LOG_PATH:halt_on_error=0"
    echo "echo \"export ASAN_OPTIONS=$CUSTOM_ASAN_OPTIONS\"" >> "$GEN_PATH"

    CUSTOM_LD_PRELOAD="\$LD_PRELOAD:$ASAN_SO_PATH"
    echo "echo \"export LD_PRELOAD=$CUSTOM_LD_PRELOAD\"" >> "$GEN_PATH"

    # Apply patch to avoid hanging and setting system-wide LD_PRELOAD.
    # Also: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=71962.
    cat <<EOF | git apply --verbose -
diff --git a/gpMgmt/bin/gppylib/commands/base.py b/gpMgmt/bin/gppylib/commands/base.py
index 138ffc679c7..6b73dd69020 100755
--- a/gpMgmt/bin/gppylib/commands/base.py
+++ b/gpMgmt/bin/gppylib/commands/base.py
@@ -450,8 +450,14 @@ class LocalExecutionContext(ExecutionContext):
         for k in keys:
             cmd.cmdStr = "%s=%s && %s" % (k, cmd.propagate_env_map[k], cmd.cmdStr)

+        # ps and pgrep hang due to us screwing with LD_PRELOAD, this is a
+        # hack to avoid glibc locales exploding
+        cmd.cmdStr = cmd.cmdStr.replace("ps -ef", "unset LD_PRELOAD; ps -ef")
+        cmd.cmdStr = cmd.cmdStr.replace("pgrep", "unset LD_PRELOAD; pgrep")
+
         # executable=(path of bash) is to ensure the shell is bash.  bash isn't the
         # actual command executed, but the shell that command string runs under.
+        print("running local command: ", cmd.cmdStr)
         self.proc = gpsubprocess.Popen(cmd.cmdStr, env=None, shell=True,
                                        start_new_session=start_new_session,
                                        executable=findCmdInPath("bash"),
diff --git a/gpMgmt/bin/lib/gpcreateseg.sh b/gpMgmt/bin/lib/gpcreateseg.sh
index 47d74c7769a..ed6316596f1 100755
--- a/gpMgmt/bin/lib/gpcreateseg.sh
+++ b/gpMgmt/bin/lib/gpcreateseg.sh
@@ -93,7 +93,8 @@ CREATE_QES_PRIMARY () {
     LOG_MSG "[INFO][\$INST_COUNT]:-Start Function \$FUNCNAME"
     LOG_MSG "[INFO][\$INST_COUNT]:-Processing segment \$GP_HOSTADDRESS"
     # build initdb command
-    cmd="\$EXPORT_LIB_PATH;\$INITDB"
+    cmd=". \${GPHOME}/greenplum_path.sh;"
+    cmd="\$cmd \$EXPORT_LIB_PATH;\$INITDB"
     cmd="\$cmd -E \$ENCODING"
     cmd="\$cmd -D \$GP_DIR"
     cmd="\$cmd --locale=\$LOCALE_SETTING"
diff --git a/src/backend/gporca/libgpos/include/gpos/common/CDynamicPtrArray.h b/src/backend/gporca/libgpos/include/gpos/common/CDynamicPtrArray.h
index dbf1ec2225c..de00c54b5fa 100644
--- a/src/backend/gporca/libgpos/include/gpos/common/CDynamicPtrArray.h
+++ b/src/backend/gporca/libgpos/include/gpos/common/CDynamicPtrArray.h
@@ -159,8 +159,8 @@ public:
 		  m_elems(nullptr)
 	{
 		// do not allocate in constructor; defer allocation to first insertion
-		GPOS_CPL_ASSERT(nullptr != CleanupFn,
-						"No valid destroy function specified");
+		// GPOS_CPL_ASSERT(nullptr != CleanupFn,
+		//				"No valid destroy function specified");
 	}
 
 	// dtor

EOF
}

sourced() {
    GPSRC=`realpath $(dirname $BASH_SOURCE)`

    if ! [ -f "$GPSRC/GPHOME" ]; then
        echo "./GPHOME file does not exist. Please run this script before sourcing it."
        return 1
    fi

    GPHOME=`cat "$GPSRC/GPHOME"`

    export MASTER_HOSTNAME=`hostname`
    export MASTER_DATA_DIRECTORY="$DATADIRS/qddir/demoDataDir-1"
    export COORDINATOR_DATA_DIRECTORY=$MASTER_DIRECTORY

    export DATADIRS="$GPSRC/gpAux/gpdemo/datadirs"
    export PGPORT="7000"

    # A command that runs 'cat' on every file with an sanitizer error for
    # programs from source folder.
    show_asan_errors() {
        LOG_DIR=`dirname $ASAN_LOG_PATH`

        for f in `ls $LOG_DIR`; do
            if grep "$GPSRC" > "/dev/null" $LOG_DIR/$f; then
                cat $LOG_DIR/$f;
            fi;
        done
    }

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
    echo "Saved '$PREFIX' to ./GPHOME"

    COMMON_CFLAGS="\
-O0 \
-g3 \
-fuse-ld=$LD"

    ASAN_CFLAGS="\
-fsanitize=address \
-fsanitize=undefined \
-fsanitize-recover=address \
-fno-omit-frame-pointer"

    ERROR_CFLAGS="\
-Wno-error=uninitialized \
-Wno-error=maybe-uninitialized \
-Wno-error=nonnull-compare \
-Wno-error=implicit-function-declaration"

    DEBUG_DEFS="\
-DEXTRA_DYNAMIC_MEMORY_DEBUG \
-DCDB_MOTION_DEBUG"

    echo -n "PREFIX='$PREFIX'. Enter to continue."
    read _

    export LDFLAGS="\
$ASAN_CFLAGS \
-fPIE \
-fPIC \
-ldl \
-lasan \
-Wl,--no-as-needed"

    export CFLAGS="\
$DEBUG_DEFS \
$COMMON_CFLAGS \
$ERROR_CFLAGS \
$LDFLAGS"

    export CXXFLAGS="\
$COMMON_CFLAGS \
$ASAN_CFLAGS \
$LDFLAGS"

    export AUTOCONF_FLAGS="\
--with-python \
--enable-depend \
--enable-debug-extensions \
--enable-cassert \
--enable-gpcloud \
--enable-orafce \
--enable-tap-tests \
--with-libxml \
--with-openssl \
--with-zstd \
--with-llvm \
--with-perl"

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

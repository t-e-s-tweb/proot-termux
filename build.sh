#!/bin/bash

NDK_FILENAME="android-ndk-r29"
TALLOC_FILENAME="talloc-2.4.3"
ARCHS='aarch64 x86_64 armv7a'
API=34

# Needed for compiling aarch64 proot
sudo apt-get install gawk -y

if [ ! -d "${NDK_FILENAME}" ] ; then

    wget "https://dl.google.com/android/repository/${NDK_FILENAME}-linux.zip"

    unzip "${NDK_FILENAME}-linux.zip"

    rm -rf "${NDK_FILENAME}-linux.zip"

else

    echo -e "NDK already installed"

fi


if [ ! -d "${TALLOC_FILENAME}" ] ; then

    wget -O "${TALLOC_FILENAME}".tar.gz "https://download.samba.org/pub/talloc/${TALLOC_FILENAME}.tar.gz"

    tar -xvzf "${TALLOC_FILENAME}.tar.gz"

    rm -rf "${TALLOC_FILENAME}.tar.gz"

else 

    echo -e "Found ${TALLOC_FILENAME}"

fi

if [ -d "output" ] ; then

    rm -rf output

fi

mkdir output


export CFLAGS="$CFLAGS -D__ANDROID_API__=${API}"

export NDK="$(pwd)/${NDK_FILENAME}"
export HOST_TAG="linux-$(uname -m)"
export TOOLCHAIN="${NDK}/toolchains/llvm/prebuilt/$HOST_TAG"

export AR="${TOOLCHAIN}/bin/llvm-ar"
export AS="${TOOLCHAIN}/bin/llvm-as"
export LD="${TOOLCHAIN}/bin/llvm-ld"
export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
export STRIP="${TOOLCHAIN}/bin/llvm-strip"

cd "${TALLOC_FILENAME}"

cat << EOF > "answers.txt"
Checking simple C program: OK
building library support: OK
Checking for large file support: OK
Checking for -D_FILE_OFFSET_BITS=64: OK
Checking for -D_LARGE_FILES: OK
Checking for WORDS_BIGENDIAN: OK
Checking for C99 vsnprintf: OK
Checking for HAVE_SECURE_MKSTEMP: OK
Checking uname sysname type: "Linux"
Checking uname machine type: "dontcare"
Checking uname release type: "dontcare"
Checking uname version type: "dontcare"
rpath library support: OK
-Wl,--version-script support: FAIL
Checking getconf LFS_CFLAGS: OK
Checking for large file support without additional flags: OK
Checking correct behavior of strtoll: OK
Checking for working strptime: OK
Checking for HAVE_SHARED_MMAP: OK
Checking for HAVE_MREMAP: OK
Checking for HAVE_INCOHERENT_MMAP: OK
Checking getconf large file support flags work: OK
EOF

# Compile static talloc
for ARCH in $ARCHS 
do

    export TARGET_TAG=$ARCH

    if [ "$ARCH" == 'armv7a' ] ; then
        export CC="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-androideabi${API}-clang"
        export CXX="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-androideabi${API}-clang++"
    else
        export CC="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-android${API}-clang"
        export CXX="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-android${API}-clang++"
    fi

    export NDK_CPUFLAGS=""

    mkdir "../output/${ARCH}"
    mkdir "../output/${ARCH}/include"
    mkdir "../output/${ARCH}/lib"
    mkdir "../output/${ARCH}/proot"

    make distclean

    ./configure build --disable-python --cross-compile --cross-answers=answers.txt --disable-rpath --bundled-libraries=NONE

    "$AR" rcs "../output/${ARCH}/lib/libtalloc.a" bin/default/talloc*.o
    cp -f talloc.h "../output/${ARCH}/include"

done

cd ../src

# Compile proot
for ARCH in $ARCHS 
do

    make distclean 

    export TARGET_TAG=$ARCH

    if [ "$ARCH" == 'armv7a' ] ; then
        export CC="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-androideabi${API}-clang"
        export CXX="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-androideabi${API}-clang++"
    else
        export CC="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-android${API}-clang"
        export CXX="${TOOLCHAIN}/bin/${TARGET_TAG}-linux-android${API}-clang++"
    fi

    export CFLAGS="-I../output/${ARCH}/include -Wno-implicit-function-declaration"
    export LDFLAGS="-L../output/${ARCH}/lib"

    export PROOT_UNBUNDLE_LOADER="../output/${ARCH}/proot"

    make V=1 "PREFIX=../output/${ARCH}/proot" install

    mv "../output/${ARCH}/proot/bin/proot" "../output/${ARCH}/proot/bin/libproot.so"
    mv "../output/${ARCH}/proot/loader" "../output/${ARCH}/proot/bin/libloader.so"

    if [ "$ARCH" != 'armv7a' ] ; then
        mv "../output/${ARCH}/proot/loader32"  "../output/${ARCH}/proot/bin/libloader32.so"
    fi

    "$STRIP" "../output/${ARCH}/proot/bin/libproot.so"
    "$STRIP" "../output/${ARCH}/proot/bin/libloader.so"

    if [ "$ARCH" != 'armv7a' ] ; then
        "$STRIP" "../output/${ARCH}/proot/bin/libloader32.so"
    fi

cat << EOF > "../output/${ARCH}/proot/bin/libprootwrapper.so"
    #!/system/bin/sh

    dir="\$(cd "\$(dirname "\$0")"; pwd)"

    unset LD_PRELOAD
    export LD_LIBRARY_PATH="\$dir"
    export PROOT_LOADER="\$dir/libloader.so"
    $(if [ "$ARCH" != 'armv7a' ]; then echo "export PROOT_LOADER_32=\"\$dir/libloader32.so\""; fi)

    exec "\$dir/libproot.so" "\$@"
EOF

done

cd ../

#!/bin/bash
# Slimmed 64-bit-only build driver, adapted from zhongfly/mpv-winbuild's
# build.sh (simple_package=true; no mpv-packaging download — only the mpv-dev
# .7z with libmpv-2.dll is needed). Usage:
#     bash build-64.sh [compiler] [mpv_ref]
# compiler: clang (default) or gcc. mpv_ref: passed to cmake as MPV_GIT_TAG
# (see packages/mpv.cmake); empty tracks origin/master.
set -x
set -euo pipefail

gitdir=$(pwd)
clang_root=$(pwd)/clang_root
buildroot=$(pwd)
srcdir=$(pwd)/src_packages
compiler=${1:-clang}
mpv_ref=${2:-}

mkdir -p ./release

build() {
    local clang_option=()
    if [ "$compiler" == "clang" ]; then
        clang_option=(-DCMAKE_INSTALL_PREFIX=$clang_root -DMINGW_INSTALL_PREFIX=$buildroot/build64/install/x86_64-w64-mingw32 -DCLANG_PACKAGES_LTO=ON)
    fi
    local mpv_tag_option=()
    if [ -n "$mpv_ref" ]; then
        mpv_tag_option=(-DMPV_GIT_TAG="$mpv_ref")
    fi
    cmake -Wno-dev --fresh -DTARGET_ARCH=x86_64-w64-mingw32 -DCOMPILER_TOOLCHAIN=$compiler "${clang_option[@]}" "${mpv_tag_option[@]}" -DENABLE_CCACHE=ON -DSINGLE_SOURCE_LOCATION=$srcdir -DRUSTUP_LOCATION=$buildroot/install_rustup -G Ninja -H$gitdir -B$buildroot/build64

    ninja -C $buildroot/build64 download || true

    if [ "$compiler" == "gcc" ] && [ ! -f "$buildroot/build64/install/bin/cross-gcc" ]; then
        ninja -C $buildroot/build64 gcc && rm -rf $buildroot/build64/toolchain
    elif [ "$compiler" == "clang" ] && [ ! "$(ls -A $clang_root/bin/clang 2>/dev/null)" ]; then
        ninja -C $buildroot/build64 llvm && ninja -C $buildroot/build64 llvm-clang
    fi

    if [[ ! "$(ls -A $buildroot/install_rustup/.cargo/bin 2>/dev/null)" ]]; then
        ninja -C $buildroot/build64 rustup-fullclean
        ninja -C $buildroot/build64 rustup
    fi
    ninja -C $buildroot/build64 update
    ninja -C $buildroot/build64 mpv-fullclean

    ninja -C $buildroot/build64 mpv

    if [ -n "$(find $buildroot/build64 -maxdepth 1 -type d -name "mpv*x86_64*" -print -quit)" ] ; then
        echo "Successfully compiled 64-bit. Continue"
    else
        echo "Failed compiled 64-bit. Stop"
        exit 1
    fi

    ninja -C $buildroot/build64 cargo-clean
}

zip_packages() {
    mv $buildroot/build64/mpv-* $gitdir/release
    cd $gitdir/release
    for dir in ./mpv*x86_64*; do
        if [ -d "$dir" ]; then
            7z a -m0=lzma2 -mx=9 -ms=on "$dir.7z" "$dir/*" -x!'*.7z'
            rm -rf "$dir"
        fi
    done
    cd ..
}

build
zip_packages
sudo rm -rf $buildroot/build64/mpv-* 2>/dev/null || true
sudo chmod -R a+rwx $buildroot/build64 2>/dev/null || true

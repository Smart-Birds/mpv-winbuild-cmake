#!/bin/bash
# Slimmed 64-bit-only build driver, adapted from zhongfly/mpv-winbuild's
# build.sh (simple_package=true; no mpv-packaging download — only the mpv-dev
# .7z with libmpv-2.dll is needed). Usage:
#     bash build-64.sh [compiler] [mpv_ref]
# compiler: clang (default) or gcc. mpv_ref: passed to cmake as MPV_GIT_TAG
# (see packages/mpv.cmake); empty tracks origin/master.
set -x
set -euo pipefail

# GHA container jobs run as root but keep HOME=/github/home; git 2.35+ refuses
# to run when $HOME does not match the euid home directory.
if [ "$(id -u)" = "0" ] && [ "${HOME:-}" = "/github/home" ]; then
    export HOME=/root
fi

gitdir=$(pwd)
clang_root=$(pwd)/clang_root
buildroot=$(pwd)
srcdir=$(pwd)/src_packages
compiler=${1:-clang}
mpv_ref=${2:-}

mkdir -p ./release

# Package PATCH_COMMANDs apply patches with `git am`, which refuses to run
# without a committer identity (bare containers have none).
git config --global user.email "mpv-winbuild@localhost"
git config --global user.name "mpv-winbuild CI"

dump_stamp_logs() {
    local kind
    for kind in err build-out configure-out install-out; do
        find "$buildroot/build64" -path "*-stamp/*-${kind}.log" -size +0c -print0 \
            | sort -z \
            | while IFS= read -r -d '' log; do
                echo "=== ${log} ==="
                tail -n 120 "$log"
            done
    done
}

scrub_libvpl_if_not_pinned() {
    local libvpl_src="$srcdir/libvpl"
    local libvpl_prefix="$buildroot/build64/packages/libvpl-prefix"
    local tag=""
    local needs_scrub=0

    if [ -d "$libvpl_src/.git" ]; then
        tag=$(git -C "$libvpl_src" describe --tags --exact-match 2>/dev/null || true)
        if [ "$tag" != "v2.17.0" ]; then
            needs_scrub=1
            echo "libvpl checkout is '${tag:-moving HEAD}', not v2.17.0; scrubbing cached tree" >&2
        elif [ -f "$gitdir/packages/libvpl-0001-mingw-wcscpy_s-guard.patch" ] && \
             ! grep -q 'defined(_MSC_VER)' "$libvpl_src/libvpl/src/windows/mfx_dispatcher_defs.h" 2>/dev/null; then
            needs_scrub=1
            echo "libvpl checkout lacks mingw wcscpy_s patch; scrubbing" >&2
        fi
    elif [ -d "$libvpl_prefix" ]; then
        # libvpl-removeprefix deletes the tree but leaves download stamps; the
        # next force-update then runs git reset on an empty directory.
        needs_scrub=1
        echo "libvpl prefix exists without checkout; scrubbing stale stamps" >&2
    fi

    if [ "$needs_scrub" = 1 ]; then
        rm -rf "$libvpl_src" "$libvpl_prefix"
    fi
}

build() {
    local clang_option=()
    if [ "$compiler" == "clang" ]; then
        clang_option=(-DCMAKE_INSTALL_PREFIX=$clang_root -DMINGW_INSTALL_PREFIX=$buildroot/build64/install/x86_64-w64-mingw32 -DCLANG_PACKAGES_LTO=ON)
    fi
    local mpv_tag_option=()
    if [ -n "$mpv_ref" ]; then
        mpv_tag_option=(-DMPV_GIT_TAG="$mpv_ref")
    fi
    # CI strips ccache_conf.in / CCACHE_DIR from exec.in; keep ccache off so
    # wrapper scripts do not serve objects built with a different toolchain.
    local fresh_option=(--fresh)
    if [ -f "$buildroot/build64/CMakeCache.txt" ]; then
        # Restored CI cache: reconfigure in-place so ExternalProject stamps stay
        # valid; --fresh wipes CMake state and can restart mingw header installs
        # while llvm-libcxx/cppwinrt compile against half-written headers.
        fresh_option=()
    fi
    cmake -Wno-dev "${fresh_option[@]}" -DTARGET_ARCH=x86_64-w64-mingw32 -DCOMPILER_TOOLCHAIN=$compiler "${clang_option[@]}" "${mpv_tag_option[@]}" -DENABLE_CCACHE=OFF -DSINGLE_SOURCE_LOCATION=$srcdir -DRUSTUP_LOCATION=$buildroot/install_rustup -G Ninja -H$gitdir -B$buildroot/build64

    # Downloads must genuinely complete: a killed parallel git clone leaves
    # stale .git locks and missing objects, and the surviving "downloaded"
    # stamps then poison every later step (llvm build, force-update). Retry
    # transient failures; on repeated failure wipe sources AND their download
    # stamps so the retry really re-clones instead of trusting corrupt state.
    for attempt in 1 2 3; do
        if ninja -C $buildroot/build64 download; then
            break
        fi
        if [ "$attempt" = 3 ]; then
            echo "ninja download failed after 3 attempts" >&2
            exit 1
        fi
        echo "download attempt $attempt failed; wiping src_packages and retrying" >&2
        # mkdir -p: git clone creates the per-package leaf dirs but needs
        # src_packages itself to exist.
        rm -rf "$srcdir" && mkdir -p "$srcdir"
        find $buildroot/build64 -path "*-stamp/*" -name "*-download" -delete
        sleep 5
    done

    if [ "$compiler" == "gcc" ] && [ ! -f "$buildroot/build64/install/bin/cross-gcc" ]; then
        ninja -C $buildroot/build64 gcc && rm -rf $buildroot/build64/toolchain
    elif [ "$compiler" == "clang" ]; then
        if [ ! -f "$clang_root/bin/clang" ]; then
            ninja -C $buildroot/build64 llvm
        fi
        # Resume or rebuild the mingw+libc++ toolchain. The llvm-libcxx-install
        # stamp file is not always present in cached trees; libstdc++.a is the
        # install artifact libc++ copies into the mingw prefix.
        local mingw_libcxx="$buildroot/build64/install/x86_64-w64-mingw32/lib/libstdc++.a"
        if [ -f "$clang_root/bin/clang" ] && [ -f "$mingw_libcxx" ]; then
            echo "mingw libc++ present; skipping llvm-clang rebuild" >&2
        else
            if [ -f "$clang_root/bin/clang" ]; then
                echo "mingw libc++ not installed; scrubbing partial mingw/libcxx/cppwinrt" >&2
                ninja -C $buildroot/build64 \
                    mingw-w64-headers-liteclean \
                    llvm-libcxx-liteclean \
                    cppwinrt-liteclean || true
            fi
            ninja -C $buildroot/build64 -j1 mingw-w64-headers mingw-w64-crt
            ninja -C $buildroot/build64 -j1 llvm-clang
        fi
    fi

    if [[ ! "$(ls -A $buildroot/install_rustup/.cargo/bin 2>/dev/null)" ]]; then
        ninja -C $buildroot/build64 rustup-fullclean
        ninja -C $buildroot/build64 rustup
    fi
    scrub_libvpl_if_not_pinned
    if [ -f "$buildroot/build64/packages/libvpl-prefix/src/libvpl-stamp/libvpl-build" ] && \
       [ ! -f "$buildroot/build64/packages/libvpl-prefix/src/libvpl-stamp/libvpl-install" ]; then
        echo "libvpl build previously failed; liteclean before retry" >&2
        ninja -C $buildroot/build64 libvpl-liteclean || true
    fi
    ninja -C $buildroot/build64 update
    ninja -C $buildroot/build64 mpv-fullclean

    if ! ninja -C $buildroot/build64 mpv; then
        dump_stamp_logs >&2
        exit 1
    fi

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

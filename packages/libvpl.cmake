ExternalProject_Add(libvpl
    GIT_REPOSITORY https://github.com/intel/libvpl.git
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    GIT_REMOTE_NAME origin
    # Pinned: upstream shinchiro built API 2.17 successfully; tracking main
    # broke SOVA2 cross-builds when libvpl moved ahead of the toolchain.
    GIT_TAG v2.17.0
    GIT_RESET v2.17.0
    UPDATE_COMMAND ""
    PATCH_COMMAND ${EXEC} sed -i "s/#if _MSC_VER < 1400/#if defined(_MSC_VER) \\&\\& _MSC_VER < 1400/" libvpl/src/windows/mfx_dispatcher_defs.h
    CONFIGURE_COMMAND ${EXEC} CONF=1 cmake -H<SOURCE_DIR> -B<BINARY_DIR>
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
        -DCMAKE_INSTALL_PREFIX=${MINGW_INSTALL_PREFIX}
        -DCMAKE_FIND_ROOT_PATH=${MINGW_INSTALL_PREFIX}
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTS=OFF   
        -DBUILD_EXAMPLES=OFF
        -DBUILD_EXPERIMENTAL=OFF        
        -DINSTALL_DEV=ON
        -DINSTALL_LIB=ON
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(libvpl)
cleanup(libvpl install)

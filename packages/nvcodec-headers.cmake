ExternalProject_Add(nvcodec-headers
    # git.videolan.org (their legacy cgit host, distinct from the working
    # code.videolan.org GitLab) does not support --filter=tree:0 and drops
    # the connection mid-fetch; use the official FFmpeg GitHub mirror.
    GIT_REPOSITORY https://github.com/FFmpeg/nv-codec-headers.git
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${MAKE} -C <SOURCE_DIR>
        PREFIX=${MINGW_INSTALL_PREFIX}
        install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(nvcodec-headers)
cleanup(nvcodec-headers install)

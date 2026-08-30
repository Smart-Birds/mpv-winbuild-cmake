ExternalProject_Add(mingw-w64
    GIT_REPOSITORY https://github.com/mingw-w64/mingw-w64.git
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    # Pinned: master is mid CRT-header refactor (2026-08-29..30) that broke
    # llvm-libcxx (_wcsicmp/stralign.h) and CRT declarations downstream.
    # v14.0.0 (2026-03-24) is the last release predating the refactor.
    # GIT_REMOTE_NAME must be set alongside GIT_TAG or force_rebuild_git
    # writes an empty reset ref (see cmake/custom_steps.cmake).
    GIT_REMOTE_NAME origin
    GIT_TAG v14.0.0
    GIT_RESET v14.0.0
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
    LOG_DOWNLOAD 1 LOG_UPDATE 1
)

force_rebuild_git(mingw-w64)
get_property(MINGW_SRC TARGET mingw-w64 PROPERTY _EP_SOURCE_DIR)
